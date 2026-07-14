"""
Portfolio management and analytics API routes.
"""

from typing import Optional
from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.portfolio import (
    PortfolioCreate,
    PortfolioResponse,
    PortfolioSummary,
    NetWorthHistory,
)
from app.services.portfolio_service import (
    create_holding,
    get_portfolio_summary,
    get_net_worth_history,
)
from app.services.risk_engine import get_risk_profile, ASSET_EXPLANATIONS, get_scheme_suggestions
from app.routers._deps import get_current_user

router = APIRouter(prefix="/portfolio", tags=["Portfolio"])


@router.get(
    "/summary",
    response_model=PortfolioSummary,
    summary="Get portfolio summary",
)
async def portfolio_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get aggregated portfolio analytics with CAGR, returns, and allocation."""
    return await get_portfolio_summary(db, current_user.id)


@router.get(
    "/net-worth-history",
    response_model=NetWorthHistory,
    summary="Get net worth chart data",
)
async def net_worth_chart(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get historical net worth data points for line chart visualization."""
    return await get_net_worth_history(db, current_user.id)


@router.post(
    "/holdings",
    response_model=PortfolioResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a holding",
)
async def add_holding(
    data: PortfolioCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Add a new investment holding to the portfolio."""
    holding = await create_holding(db, current_user.id, data)

    return PortfolioResponse(
        id=holding.id,
        user_id=holding.user_id,
        asset_name=holding.asset_name,
        asset_type=holding.asset_type,
        current_value=float(holding.current_value),
        initial_investment=float(holding.initial_investment),
        calculated_xirr=holding.calculated_xirr,
        calculated_cagr=holding.calculated_cagr,
        absolute_return=holding.absolute_return,
        return_percentage=holding.return_percentage,
        start_date=holding.start_date,
        value_history=holding.value_history,
        last_updated=holding.last_updated,
        created_at=holding.created_at,
    )


from pydantic import BaseModel
from datetime import datetime, timezone

class InvestmentConfirmRequest(BaseModel):
    asset_type: str
    scheme_name: str
    suggested_amount: float
    actual_amount: float
    confirmed: bool
    advisor_id: Optional[str] = None
    investment_mode: Optional[str] = "sip"


@router.get(
    "/advisor",
    summary="Get investment advice",
)
async def investment_advisor(current_user: User = Depends(get_current_user)):
    risk_profile = current_user.risk_profile
    if not risk_profile or "score" not in risk_profile:
        return {"has_profile": False}

    profile = get_risk_profile(risk_profile["score"])
    allocation = profile["recommended_allocation"]

    from app.services.budget_calculator import _get_monthly_income, _get_savings_floor_pct
    income = _get_monthly_income(current_user)
    savings_pct = _get_savings_floor_pct(current_user)
    monthly_investable = income * savings_pct

    scheme_suggestions = await get_scheme_suggestions(
        profile["level"], allocation, current_user
    )

    return {
        "has_profile": True,
        "risk_level": profile["level"],
        "risk_score": profile["score"],
        "description": profile["description"],
        "recommended_allocation": allocation,
        "asset_explanations": profile["asset_explanations"],
        "monthly_investable": monthly_investable,
        "scheme_suggestions": scheme_suggestions,
    }


@router.post("/advisor/confirm-investment")
async def confirm_investment(
    data: InvestmentConfirmRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    User confirms they made (or skipped) an advised investment.
    If confirmed, auto-creates a Portfolio holding entry and optional ARN linkage.
    """
    from datetime import date
    from app.models.investment_confirmation import InvestmentConfirmation
    from app.models.portfolio import Portfolio
    from app.models.arn_linkage import ArnLinkage

    conf = InvestmentConfirmation(
        user_id=current_user.id,
        asset_type=data.asset_type,
        scheme_name=data.scheme_name,
        suggested_amount=data.suggested_amount,
        actual_amount=data.actual_amount,
        confirmed=data.confirmed,
        confirmed_at=datetime.now(timezone.utc) if data.confirmed else None,
    )
    db.add(conf)

    advisor_arn = None
    if data.confirmed and data.actual_amount > 0:
        if data.advisor_id:
            # Resolve advisor ARN
            adv_res = await db.execute(
                select(User).where(User.id == data.advisor_id, User.user_type == "advisor")
            )
            advisor = adv_res.scalar_one_or_none()
            if advisor:
                advisor_arn = advisor.arn_number or "ARN-00000"
                # Establish ARN Linkage if not already exists
                link_res = await db.execute(
                    select(ArnLinkage).where(
                        ArnLinkage.investor_id == current_user.id,
                        ArnLinkage.advisor_id == data.advisor_id,
                        ArnLinkage.is_active == True,
                    )
                )
                if not link_res.scalar_one_or_none():
                    linkage = ArnLinkage(
                        investor_id=current_user.id,
                        advisor_id=data.advisor_id,
                        arn_number=advisor_arn,
                        is_active=True,
                    )
                    db.add(linkage)

        holding = Portfolio(
            user_id=current_user.id,
            asset_name=data.scheme_name,
            asset_type=data.asset_type,
            current_value=data.actual_amount,
            initial_investment=data.actual_amount,
            start_date=date.today(),
            advisor_id=data.advisor_id,
            advisor_arn=advisor_arn,
            investment_mode=data.investment_mode,
        )
        db.add(holding)

    await db.commit()
    return {"message": "Investment recorded", "portfolio_updated": data.confirmed}
