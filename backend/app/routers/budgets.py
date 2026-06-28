from typing import Optional
"""
Budget management API routes.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.budget import BudgetCreate, BudgetResponse, BudgetWarning
from app.services.budget_service import get_user_budgets, create_budget
from app.routers._deps import get_current_user

router = APIRouter(prefix="/budgets", tags=["Budgets"])


@router.get(
    "/",
    response_model=list[BudgetResponse],
    summary="Get all budgets",
)
async def list_budgets(
    month_year: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch all budgets for the current user, optionally filtered by month."""
    budgets = await get_user_budgets(db, current_user.id, month_year)

    return [
        BudgetResponse(
            id=b.id,
            user_id=b.user_id,
            category=b.category,
            limit_amount=float(b.limit_amount),
            current_spent=float(b.current_spent),
            month_year=b.month_year,
            spent_percentage=round(b.spent_percentage, 1),
            remaining=round(b.remaining, 2),
            threshold_status=b.threshold_status,
            alert_70_sent=b.alert_70_sent,
            alert_85_sent=b.alert_85_sent,
            created_at=b.created_at,
        )
        for b in budgets
    ]


@router.post(
    "/",
    response_model=BudgetResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a budget",
)
async def create_new_budget(
    data: BudgetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new category budget for a specific month."""
    budget = await create_budget(db, current_user.id, data)

    return BudgetResponse(
        id=budget.id,
        user_id=budget.user_id,
        category=budget.category,
        limit_amount=float(budget.limit_amount),
        current_spent=float(budget.current_spent),
        month_year=budget.month_year,
        spent_percentage=round(budget.spent_percentage, 1),
        remaining=round(budget.remaining, 2),
        threshold_status=budget.threshold_status,
        alert_70_sent=budget.alert_70_sent,
        alert_85_sent=budget.alert_85_sent,
        created_at=budget.created_at,
    )
