from typing import Optional
"""
Budget service.
Handles budget CRUD, spending updates, and threshold detection for notifications.
"""

from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.budget import Budget
from app.schemas.budget import BudgetCreate, BudgetWarning


async def get_user_budgets(
    db: AsyncSession, user_id: str, month_year: Optional[str] = None
) -> list[Budget]:
    """Fetch all budgets for a user, optionally filtered by month."""
    query = select(Budget).where(Budget.user_id == user_id)
    if month_year:
        query = query.where(Budget.month_year == month_year)
    query = query.order_by(Budget.category)

    result = await db.execute(query)
    return list(result.scalars().all())


async def create_budget(
    db: AsyncSession, user_id: str, data: BudgetCreate
) -> Budget:
    """Create a new budget entry."""
    budget = Budget(
        user_id=user_id,
        category=data.category.lower(),
        limit_amount=data.limit_amount,
        current_spent=0.00,
        month_year=data.month_year,
    )
    db.add(budget)
    await db.flush()
    await db.refresh(budget)
    return budget


async def update_spending(
    db: AsyncSession, budget_id: str, amount: float
) -> tuple[Budget, list[BudgetWarning]]:
    """
    Add spending to a budget and check thresholds.
    Returns the updated budget and any new warnings triggered.
    """
    result = await db.execute(select(Budget).where(Budget.id == budget_id))
    budget = result.scalar_one_or_none()

    if budget is None:
        raise ValueError(f"Budget {budget_id} not found")

    budget.current_spent = float(budget.current_spent) + amount
    budget.updated_at = datetime.now(timezone.utc)

    warnings = check_thresholds(budget)

    db.add(budget)
    await db.flush()
    await db.refresh(budget)

    return budget, warnings


def check_thresholds(budget: Budget) -> list[BudgetWarning]:
    """
    Check if budget has crossed warning thresholds.
    Returns list of new warnings (idempotent — won't re-fire).
    """
    warnings: list[BudgetWarning] = []
    pct = budget.spent_percentage

    # 85% threshold (danger)
    if pct >= 85 and not budget.alert_85_sent:
        budget.alert_85_sent = True
        warnings.append(
            BudgetWarning(
                budget_id=budget.id,
                category=budget.category,
                threshold=85,
                spent_percentage=round(pct, 1),
                remaining_amount=round(budget.remaining, 2),
                message=(
                    f"🚨 Alert: You've spent {pct:.0f}% of your {budget.category} budget! "
                    f"Only ₹{budget.remaining:,.0f} remaining for this month."
                ),
            )
        )

    # 70% threshold (warning)
    elif pct >= 70 and not budget.alert_70_sent:
        budget.alert_70_sent = True
        warnings.append(
            BudgetWarning(
                budget_id=budget.id,
                category=budget.category,
                threshold=70,
                spent_percentage=round(pct, 1),
                remaining_amount=round(budget.remaining, 2),
                message=(
                    f"⚠️ Heads up: You've used {pct:.0f}% of your {budget.category} budget. "
                    f"₹{budget.remaining:,.0f} left for the rest of the month."
                ),
            )
        )

    return warnings


async def add_transaction_to_budget(
    db: AsyncSession, user_id: str, category: str, amount: float, month_year: str
) -> list[BudgetWarning]:
    """
    After a transaction is recorded, update the corresponding budget's spending.
    Creates the budget if it doesn't exist for that category/month.
    Returns any triggered warnings.
    """
    result = await db.execute(
        select(Budget).where(
            Budget.user_id == user_id,
            Budget.category == category.lower(),
            Budget.month_year == month_year,
        )
    )
    budget = result.scalar_one_or_none()

    if budget is None:
        # No budget set for this category/month — no warnings to fire
        return []

    _, warnings = await update_spending(db, budget.id, amount)
    return warnings
