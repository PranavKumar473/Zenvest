"""
Mutual fund data API routes.
Real fund identity + returns computed from AMFI-linked NAV history
(see app/services/mutual_fund_service.py) — no fabricated figures.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status

from app.models.user import User
from app.routers._deps import get_current_user
from app.services.mutual_fund_service import get_fund_detail, get_suggestions_for_risk_level
from app.services.risk_engine import get_risk_profile

router = APIRouter(prefix="/mutual-funds", tags=["Mutual Funds"])


@router.get(
    "/suggestions",
    summary="Get real mutual fund suggestions for the current user's risk level",
)
async def list_suggestions(
    risk_level: Optional[str] = None,
    current_user: User = Depends(get_current_user),
):
    """
    Returns real, live-computed fund summaries (name, fund house, category,
    NAV, 1Y/3Y/5Y returns) for the given risk level, or the current user's
    own risk profile if none is passed.
    """
    level = risk_level
    if not level:
        risk_profile = current_user.risk_profile
        if not risk_profile or "score" not in risk_profile:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Complete your risk assessment first, or pass ?risk_level=",
            )
        level = get_risk_profile(risk_profile["score"])["level"]

    funds = await get_suggestions_for_risk_level(level)
    return {"risk_level": level, "funds": funds}


@router.get(
    "/{scheme_code}",
    summary="Get full fund detail — returns, yearly performance, NAV chart",
)
async def fund_detail(
    scheme_code: int,
    current_user: User = Depends(get_current_user),
):
    detail = await get_fund_detail(scheme_code)
    if not detail:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Fund not found or NAV data temporarily unavailable",
        )
    return detail
