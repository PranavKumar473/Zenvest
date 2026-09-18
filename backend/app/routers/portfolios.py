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
    User confirms they made (or skipped) an advised investment from the
    advisor screen. Delegates to the shared investment_service so every
    entry point (this screen, the universal /invest flow, fund directory,
    top-5 recommendations) executes under the same corporate-ARN routing
    and advisor-attribution rules — see app/services/investment_service.py.
    """
    from app.services.investment_service import record_investment

    result = await record_investment(
        db,
        investor=current_user,
        asset_type=data.asset_type,
        scheme_name=data.scheme_name,
        suggested_amount=data.suggested_amount,
        actual_amount=data.actual_amount,
        confirmed=data.confirmed,
        investment_mode=data.investment_mode,
        advisor_source="human" if data.advisor_id else "robo",
        advisor_id=data.advisor_id,
    )
    return {"message": result["message"], "portfolio_updated": data.confirmed}
