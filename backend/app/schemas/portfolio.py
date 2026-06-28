from typing import Optional
"""
Portfolio request/response schemas.
"""

from datetime import datetime, date
from pydantic import BaseModel, Field


class PortfolioCreate(BaseModel):
    """Create a new portfolio holding."""
    asset_name: str = Field(..., max_length=200, examples=["HDFC Balanced Advantage Fund"])
    asset_type: str = Field(
        ...,
        description="Asset class",
        examples=["mutual_fund"],
    )
    current_value: float = Field(..., ge=0, examples=[125000.00])
    initial_investment: float = Field(..., gt=0, examples=[100000.00])
    start_date: date = Field(..., examples=["2025-01-15"])
    cash_flows: Optional[list[dict]] = Field(
        None,
        description="Cash flow records for XIRR calculation",
        examples=[[{"date": "2025-01-15", "amount": -100000}]],
    )


class PortfolioResponse(BaseModel):
    """Single portfolio holding response."""
    id: str
    user_id: str
    asset_name: str
    asset_type: str
    current_value: float
    initial_investment: float
    calculated_xirr: Optional[float] = None
    calculated_cagr: Optional[float] = None
    absolute_return: float
    return_percentage: float
    start_date: date
    value_history: Optional[list[dict]] = None
    last_updated: datetime
    created_at: datetime

    model_config = {"from_attributes": True}


class PortfolioSummary(BaseModel):
    """Aggregated portfolio summary."""
    total_invested: float
    total_current_value: float
    total_return: float
    total_return_percentage: float
    portfolio_cagr: Optional[float] = None
    portfolio_xirr: Optional[float] = None
    holdings: list[PortfolioResponse]
    asset_allocation: dict[str, float] = Field(
        description="Percentage allocation by asset type"
    )


class NetWorthDataPoint(BaseModel):
    """Single net worth data point for charting."""
    date: str = Field(examples=["2026-01"])
    value: float = Field(examples=[524000.00])


class NetWorthHistory(BaseModel):
    """Net worth history for line chart."""
    data_points: list[NetWorthDataPoint]
    current_net_worth: float
    growth_percentage: float = Field(description="Growth from first to last data point")
