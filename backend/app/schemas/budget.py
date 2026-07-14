from typing import Optional
"""
Budget request/response schemas.
"""

from datetime import datetime
from pydantic import BaseModel, Field


class BudgetCreate(BaseModel):
    """Create a new budget entry."""
    category: str = Field(
        ...,
        description="Budget category",
        examples=["food"],
    )
    limit_amount: float = Field(
        ...,
        gt=0,
        description="Monthly budget limit in INR",
        examples=[15000.00],
    )
    month_year: str = Field(
        ...,
        pattern=r"^\d{4}-\d{2}$",
        description="Target month in YYYY-MM format",
        examples=["2026-06"],
    )


class BudgetUpdate(BaseModel):
    """Update an existing budget."""
    limit_amount: Optional[float] = Field(None, gt=0)
    current_spent: Optional[float] = Field(None, ge=0)


class BudgetResponse(BaseModel):
    """Budget data response."""
    id: str
    user_id: str
    category: str
    limit_amount: float
    current_spent: float
    month_year: str
    spent_percentage: float
    remaining: float
    threshold_status: str  # "safe", "warning", "danger"
    alert_70_sent: bool
    alert_85_sent: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class BudgetWarning(BaseModel):
    """Budget threshold warning payload for push notifications."""
    budget_id: str
    category: str
    threshold: int = Field(description="Threshold crossed: 70 or 85")
    spent_percentage: float
    remaining_amount: float
    message: str = Field(description="Human-readable warning message")


class BudgetSuggestionItem(BaseModel):
    category: str
    suggested_limit: float
    basis: str              # human-readable explanation


class BudgetSuggestionResponse(BaseModel):
    monthly_income_used: float
    savings_floor_amount: float        # e.g. ₹20,000
    spendable_income: float            # e.g. ₹80,000
    total_suggested_spending: float    # must always equal spendable_income
    suggestions: list[BudgetSuggestionItem]
    framework_breakdown: dict   # raw per-framework numbers for the detail sheet
    savings_floor_percentage: float
    age_group: str
    risk_level: str
