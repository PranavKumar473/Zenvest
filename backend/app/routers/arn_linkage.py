"""
ARN/INA Linkage API routes.
Tracks when an investor formally attaches an advisor's regulatory
identifier to their investments — either the AMFI ARN (mutual fund
execution) or the SEBI INA (fee-only advice, no execution). Once linked,
the advisor can view the investor's active investments.
"""
from typing import Optional, Literal
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, model_validator
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.arn_linkage import ArnLinkage
from app.models.portfolio import Portfolio
from app.routers._deps import get_current_user
from app.schemas.user import UserResponse

router = APIRouter(prefix="/arn-linkage", tags=["ARN/INA Linkage"])


# ─── Schemas ────────────────────────────────────────────────────────

class LinkArnPayload(BaseModel):
    advisor_id: str
    linkage_type: Literal["ARN", "INA"] = Field(
        default="ARN",
        description="'ARN' for mutual fund execution, 'INA' for fee-only advice",
    )
    # Back-compat: existing Flutter clients only send arn_number.
    arn_number: Optional[str] = Field(None, min_length=3, max_length=20)
    ina_number: Optional[str] = Field(None, min_length=3, max_length=30)

    @model_validator(mode="after")
    def validate_number_matches_type(self):
        if self.linkage_type == "ARN" and not self.arn_number:
            raise ValueError("arn_number is required when linkage_type is 'ARN'")
        if self.linkage_type == "INA" and not self.ina_number:
            raise ValueError("ina_number is required when linkage_type is 'INA'")
        return self


class LinkageResponse(BaseModel):
    id: str
    investor_id: str
    advisor_id: str
    linkage_type: str
    arn_number: Optional[str] = None
    ina_number: Optional[str] = None
    linked_at: datetime
    is_active: bool
    advisor_name: Optional[str] = None
    investor_name: Optional[str] = None

    model_config = {"from_attributes": True}


class LinkedInvestorResponse(BaseModel):
    investor_id: str
    investor_name: str
    investor_email: str
    linked_at: datetime
    active_investments_count: int
    total_invested_value: float

    model_config = {"from_attributes": True}


# ─── Endpoints ──────────────────────────────────────────────────────

@router.post(
    "",
    response_model=LinkageResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Investor links an advisor's ARN (execution) or INA (fee-only advice)",
)
async def link_advisor_arn(
    payload: LinkArnPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Investor records that they've attached an advisor's regulatory ID to their investments."""
    if current_user.user_type != "user":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only investors can link to an advisor",
        )

    result = await db.execute(
        select(User).where(User.id == payload.advisor_id, User.user_type == "advisor")
    )
    advisor = result.scalar_one_or_none()
    if not advisor:
        raise HTTPException(status_code=404, detail="Advisor not found")

    if payload.linkage_type == "INA" and not advisor.sebi_registration_number:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This advisor has no SEBI RIA (INA) registration on file",
        )

    # For MVP, we simply allow multiple or override active ones.
    linkage = ArnLinkage(
        investor_id=current_user.id,
        advisor_id=payload.advisor_id,
        linkage_type=payload.linkage_type,
        arn_number=payload.arn_number if payload.linkage_type == "ARN" else None,
        ina_number=payload.ina_number if payload.linkage_type == "INA" else None,
        is_active=True,
    )
    db.add(linkage)
    await db.flush()
    await db.refresh(linkage)

    return LinkageResponse(
        id=linkage.id,
        investor_id=linkage.investor_id,
        advisor_id=linkage.advisor_id,
        linkage_type=linkage.linkage_type,
        arn_number=linkage.arn_number,
        ina_number=linkage.ina_number,
        linked_at=linkage.linked_at,
        is_active=linkage.is_active,
        advisor_name=advisor.advisor_name or advisor.name,
        investor_name=current_user.name,
    )


@router.get(
    "/my-advisor",
    response_model=list[LinkageResponse],
    summary="Investor gets their active linked advisors",
)
async def get_my_advisors(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve all advisors that this investor has linked with."""
    result = await db.execute(
        select(ArnLinkage)
        .where(ArnLinkage.investor_id == current_user.id, ArnLinkage.is_active == True)
        .order_by(ArnLinkage.linked_at.desc())
    )
    linkages = result.scalars().all()

    responses = []
    for l in linkages:
        adv_res = await db.execute(select(User).where(User.id == l.advisor_id))
        advisor = adv_res.scalar_one_or_none()
        responses.append(LinkageResponse(
            id=l.id,
            investor_id=l.investor_id,
            advisor_id=l.advisor_id,
            linkage_type=l.linkage_type,
            arn_number=l.arn_number,
            ina_number=l.ina_number,
            linked_at=l.linked_at,
            is_active=l.is_active,
            advisor_name=(advisor.advisor_name or advisor.name) if advisor else "Unknown",
            investor_name=current_user.name,
        ))
    return responses


@router.get(
    "/my-investors",
    response_model=list[LinkedInvestorResponse],
    summary="Advisor gets all linked investors",
)
async def get_my_investors(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve all investors who have linked to this advisor's ARN."""
    if current_user.user_type != "advisor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only advisors can view their linked investors",
        )

    result = await db.execute(
        select(ArnLinkage)
        .where(ArnLinkage.advisor_id == current_user.id, ArnLinkage.is_active == True)
        .order_by(ArnLinkage.linked_at.desc())
    )
    linkages = result.scalars().all()

    responses = []
    for l in linkages:
        inv_res = await db.execute(select(User).where(User.id == l.investor_id))
        investor = inv_res.scalar_one_or_none()
        if not investor:
            continue

        # Fetch investor's portfolios tagged with this advisor or advisor ARN
        portfolio_res = await db.execute(
            select(Portfolio).where(
                Portfolio.user_id == investor.id,
                Portfolio.advisor_id == current_user.id,
            )
        )
        portfolios = portfolio_res.scalars().all()

        total_invested = sum(p.current_value for p in portfolios)

        responses.append(LinkedInvestorResponse(
            investor_id=investor.id,
            investor_name=investor.name,
            investor_email=investor.email,
            linked_at=l.linked_at,
            active_investments_count=len(portfolios),
            total_invested_value=total_invested,
        ))

    return responses


@router.get(
    "/my-investors/{investor_id}/portfolio",
    summary="Advisor views a linked investor's portfolio details",
)
async def view_investor_portfolio(
    investor_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Advisor views the portfolio of an investor linked to them."""
    if current_user.user_type != "advisor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only advisors can view investor portfolios",
        )

    # Check linkage exists
    link_res = await db.execute(
        select(ArnLinkage).where(
            ArnLinkage.advisor_id == current_user.id,
            ArnLinkage.investor_id == investor_id,
            ArnLinkage.is_active == True,
        )
    )
    if not link_res.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not linked to this investor",
        )

    # Fetch portfolio holdings
    portfolio_res = await db.execute(
        select(Portfolio).where(
            Portfolio.user_id == investor_id,
            Portfolio.advisor_id == current_user.id,
        )
    )
    portfolios = portfolio_res.scalars().all()

    # Convert to serializable format
    return [
        {
            "id": p.id,
            "asset_name": p.asset_name,
            "asset_type": p.asset_type,
            "current_value": float(p.current_value),
            "initial_investment": float(p.initial_investment),
            "calculated_cagr": p.calculated_cagr,
            "calculated_xirr": p.calculated_xirr,
            "start_date": p.start_date.isoformat(),
            "investment_mode": p.investment_mode or "lumpsum",
        }
        for p in portfolios
    ]
