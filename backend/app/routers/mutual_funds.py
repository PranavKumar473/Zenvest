"""
Mutual fund data API routes.
Real fund identity + returns computed from AMFI-linked NAV history
(see app/services/mutual_fund_service.py) — no fabricated figures.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status

from app.models.user import User
from app.routers._deps import get_current_user
from app.services.mutual_fund_service import (
    get_fund_detail,
    get_fund_directory,
    get_suggestions_for_risk_level,
    get_top5_recommendations,
)
from app.services.risk_engine import get_risk_profile

router = APIRouter(prefix="/mutual-funds", tags=["Mutual Funds"])


@router.get(
    "/directory",
    summary="Browse the full categorized universe of available mutual funds",
)
async def fund_directory(current_user: User = Depends(get_current_user)):
    """
    Returns every catalogued fund grouped by category (Equity — Large Cap,
    Mid Cap, Small Cap, Flexi Cap, ELSS; Hybrid; Debt — Corporate Bond,
    Gilt), each with live NAV and 1Y/3Y returns.
    """
    categories = await get_fund_directory()
    return {"categories": categories}


@router.get(
    "/top5",
    summary="Top 5 recommended schemes ranked by real returns + risk-adjusted metrics",
)
async def top5_recommendations(
    risk_level: Optional[str] = None,
    current_user: User = Depends(get_current_user),
):
    """
    Ranks candidate funds by a composite percentile score built from real,
    computed data only: 3Y return, Sharpe ratio, Sortino ratio, and Alpha
    (weights 35/25/20/20, redistributed when a metric is unavailable for a
    given fund — e.g. debt funds lack Alpha/Beta). Expense Ratio isn't
    scored since no free vendor exposes it yet.

    Defaults to the current user's own risk profile if risk_level isn't
    passed.
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

    funds = await get_top5_recommendations(level)
    return {"risk_level": level, "funds": funds}


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
    "/compare",
    summary="Compare multiple mutual funds",
)
async def compare_funds(
    codes: str,
    current_user: User = Depends(get_current_user),
):
    """
    Returns full details for a comma-separated list of scheme codes.
    Allows side-by-side comparison on the client.
    """
    try:
        scheme_codes = [int(c.strip()) for c in codes.split(",") if c.strip()]
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid scheme codes format. Must be comma-separated integers.",
        )

    results = []
    for code in scheme_codes:
        detail = await get_fund_detail(code)
        if detail:
            results.append(detail)
    return {"funds": results}


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
