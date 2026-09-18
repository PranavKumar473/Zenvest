"""
Portfolio service.
Handles portfolio CRUD, XIRR/CAGR calculations, and aggregated analytics.
"""

from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.portfolio import Portfolio
from app.schemas.portfolio import (
    PortfolioCreate,
    PortfolioResponse,
    PortfolioSummary,
    NetWorthHistory,
    NetWorthDataPoint,
)
from app.utils.financial_math import calculate_xirr, calculate_cagr


async def create_holding(
    db: AsyncSession, user_id: str, data: PortfolioCreate
) -> Portfolio:
    """Create a new portfolio holding with calculated metrics."""
    # Calculate CAGR
    cagr = calculate_cagr(
        data.initial_investment,
        data.current_value,
        data.start_date,
    )

    # Calculate XIRR if cash flows provided
    xirr = None
    if data.cash_flows:
        xirr = calculate_xirr(
            data.cash_flows,
            data.current_value,
        )

    holding = Portfolio(
        user_id=user_id,
        asset_name=data.asset_name,
        asset_type=data.asset_type.lower(),
        current_value=data.current_value,
        initial_investment=data.initial_investment,
        calculated_xirr=xirr,
        calculated_cagr=cagr,
        start_date=data.start_date,
        cash_flows=data.cash_flows,
        value_history=[],
    )
    db.add(holding)
    await db.flush()
    await db.refresh(holding)
    return holding


async def get_user_holdings(
    db: AsyncSession, user_id: str
) -> list[Portfolio]:
    """Fetch all portfolio holdings for a user."""
    result = await db.execute(
        select(Portfolio)
        .where(Portfolio.user_id == user_id)
        .order_by(Portfolio.asset_type, Portfolio.asset_name)
    )
    return list(result.scalars().all())


async def get_portfolio_summary(
    db: AsyncSession, user_id: str
) -> PortfolioSummary:
    """
    Calculate aggregated portfolio metrics.
    Returns total invested, current value, returns, and allocation breakdown.
    """
    holdings = await get_user_holdings(db, user_id)

    total_invested = sum(float(h.initial_investment) for h in holdings)
    total_current = sum(float(h.current_value) for h in holdings)
    total_return = total_current - total_invested
    return_pct = (total_return / total_invested * 100) if total_invested > 0 else 0

    # Calculate portfolio-level CAGR
    portfolio_cagr = None
    if holdings:
        earliest_date = min(h.start_date for h in holdings)
        portfolio_cagr = calculate_cagr(
            total_invested, total_current, earliest_date
        )

    # Asset allocation by type
    allocation: dict[str, float] = {}
    if total_current > 0:
        type_totals: dict[str, float] = {}
        for h in holdings:
            t = h.asset_type
            type_totals[t] = type_totals.get(t, 0) + float(h.current_value)
        allocation = {
            t: round(v / total_current * 100, 1)
            for t, v in type_totals.items()
        }

    # Build responses
    holding_responses = []
    for h in holdings:
        holding_responses.append(
            PortfolioResponse(
                id=h.id,
                user_id=h.user_id,
                asset_name=h.asset_name,
                asset_type=h.asset_type,
                current_value=float(h.current_value),
                initial_investment=float(h.initial_investment),
                calculated_xirr=h.calculated_xirr,
                calculated_cagr=h.calculated_cagr,
                absolute_return=h.absolute_return,
                return_percentage=h.return_percentage,
                start_date=h.start_date,
                value_history=h.value_history,
                last_updated=h.last_updated,
                created_at=h.created_at,
            )
        )

    return PortfolioSummary(
        total_invested=round(total_invested, 2),
        total_current_value=round(total_current, 2),
        total_return=round(total_return, 2),
        total_return_percentage=round(return_pct, 2),
        portfolio_cagr=portfolio_cagr,
        holdings=holding_responses,
        asset_allocation=allocation,
    )


async def get_net_worth_history(
    db: AsyncSession, user_id: str
) -> NetWorthHistory:
    """
    Aggregate historical net worth data points from all holdings.
    Combines value_history from each holding into a monthly net worth timeline.
    """
    holdings = await get_user_holdings(db, user_id)

    # Aggregate all data points by month
    monthly_totals: dict[str, float] = {}
    for h in holdings:
        if h.value_history:
            for point in h.value_history:
                month = point.get("date", "")
                value = float(point.get("value", 0))
                monthly_totals[month] = monthly_totals.get(month, 0) + value

    # Sort chronologically
    sorted_months = sorted(monthly_totals.keys())
    data_points = [
        NetWorthDataPoint(date=m, value=round(monthly_totals[m], 2))
        for m in sorted_months
    ]

    current_net_worth = sum(float(h.current_value) for h in holdings)
    first_value = data_points[0].value if data_points else current_net_worth
    growth = (
        ((current_net_worth - first_value) / first_value * 100)
        if first_value > 0
        else 0
    )

    return NetWorthHistory(
        data_points=data_points,
        current_net_worth=round(current_net_worth, 2),
        growth_percentage=round(growth, 2),
    )
