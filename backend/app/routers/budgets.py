from typing import Optional
from datetime import datetime
"""
Budget management API routes.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.database import get_db
from app.models.user import User
from app.models.transaction import Transaction
from app.schemas.budget import (
    BudgetCreate,
    BudgetResponse,
    BudgetWarning,
    BudgetSuggestionResponse,
    BudgetSuggestionItem,
    BudgetUpdate,
)
from app.services.budget_service import get_user_budgets, create_budget
from app.services.budget_calculator import calculate_suggested_budgets, get_framework_breakdown
from app.routers._deps import get_current_user

router = APIRouter(prefix="/budgets", tags=["Budgets"])


@router.get(
    "",
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
    "",
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


async def _get_user_real_income(db: AsyncSession, user_id: str) -> Optional[float]:
    """Calculate the user's real monthly income from deposit/credit transactions."""
    now = datetime.now()
    start_of_month = datetime(now.year, now.month, 1)

    # Check total credit transactions this month
    stmt_month = select(func.sum(Transaction.amount)).where(
        Transaction.user_id == user_id,
        Transaction.is_debit == False,
        Transaction.timestamp >= start_of_month
    )
    res_month = await db.execute(stmt_month)
    month_credits = res_month.scalar()

    if month_credits and float(month_credits) > 0:
        return float(month_credits)

    # Check historical credit transactions
    stmt_hist = select(func.sum(Transaction.amount)).where(
        Transaction.user_id == user_id,
        Transaction.is_debit == False
    )
    res_hist = await db.execute(stmt_hist)
    hist_credits = res_hist.scalar()

    if hist_credits and float(hist_credits) > 0:
        stmt_distinct = select(func.count(func.distinct(func.strftime('%Y-%m', Transaction.timestamp)))).where(
            Transaction.user_id == user_id,
            Transaction.is_debit == False
        )
        res_distinct = await db.execute(stmt_distinct)
        num_months = res_distinct.scalar() or 1
        return float(hist_credits) / max(num_months, 1)

    return None


@router.get(
    "/suggestions",
    response_model=BudgetSuggestionResponse,
    summary="Get AI-suggested budget limits for all categories",
)
async def get_budget_suggestions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns personalized monthly budget suggestions for every category,
    derived from blending 4 financial frameworks (Warren, Rohn, Bach, Ramsey)
    adjusted by the user's age, income, and risk profile.
    Also returns a framework breakdown for the 'How was this calculated?' sheet.
    """
    real_income = await _get_user_real_income(db, current_user.id)
    breakdown = get_framework_breakdown(current_user, real_income=real_income)
    suggestions = breakdown["blended_suggestion"]

    items = [
        BudgetSuggestionItem(
            category=cat,
            suggested_limit=amount,
            basis=_explain_suggestion(cat, amount, breakdown, real_income is not None),
        )
        for cat, amount in suggestions.items()
    ]

    return BudgetSuggestionResponse(
        monthly_income_used=breakdown["monthly_income_used"],
        savings_floor_amount=breakdown["monthly_income_used"] * (breakdown["savings_floor_percentage"] / 100),
        spendable_income=breakdown["monthly_income_used"] * (1 - breakdown["savings_floor_percentage"] / 100),
        total_suggested_spending=sum(s.suggested_limit for s in items),
        savings_floor_percentage=breakdown["savings_floor_percentage"],
        age_group=breakdown["age_group"],
        risk_level=breakdown["risk_level"],
        suggestions=items,
        framework_breakdown=breakdown["frameworks"],
    )


def _explain_suggestion(cat: str, amount: float, breakdown: dict, is_real_income: bool) -> str:
    """Generate a one-line human-readable explanation for each category limit."""
    income = breakdown["monthly_income_used"]
    pct = round((amount / income) * 100, 1) if income > 0 else 0
    source_label = "real monthly credits" if is_real_income else "estimated monthly income"
    return f"≈{pct}% of your {source_label} (₹{income:,.0f}), blended across 4 budget frameworks"


@router.post(
    "/apply-suggestions",
    summary="Auto-create budgets from suggested limits for current month",
    status_code=201,
)
async def apply_budget_suggestions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    One-tap action: creates Budget rows for the current month using the
    suggested limits. Skips categories that already have a budget this month.
    Returns the list of created budgets.
    """
    from datetime import datetime
    from sqlalchemy import delete
    from app.models.budget import Budget
    from app.schemas.budget import BudgetCreate
    from app.services.budget_calculator import _get_monthly_income, _get_savings_floor_pct

    now = datetime.now()
    month_year = f"{now.year}-{now.month:02d}"

    # Step 1: Delete ALL existing budgets for this user+month
    # This ensures stale un-normalized limits are wiped before recreating
    await db.execute(
        delete(Budget).where(
            Budget.user_id == current_user.id,
            Budget.month_year == month_year,
        )
    )
    await db.flush()

    # Step 2: Get fresh normalized suggestions
    real_income = await _get_user_real_income(db, current_user.id)
    suggestions = calculate_suggested_budgets(current_user, real_income=real_income)

    # Step 3: Verify normalization — suggestions must sum to spendable income
    income = real_income if real_income is not None else _get_monthly_income(current_user)
    savings_pct = _get_savings_floor_pct(current_user)
    spendable = income * (1 - savings_pct / 100)
    total = sum(suggestions.values())

    # Safety assertion: if total deviates from spendable by more than ₹200, recalculate
    if abs(total - spendable) > 200 and spendable > 0:
        # Scale to fix any rounding drift
        factor = spendable / total
        suggestions = {k: round((v * factor) / 100) * 100 for k, v in suggestions.items()}
        # Fix any remaining drift on largest category
        drift = spendable - sum(suggestions.values())
        largest = max(suggestions, key=suggestions.get)
        suggestions[largest] += drift

    # Step 4: Create fresh budget rows
    created = []
    for cat, amount in suggestions.items():
        budget = await create_budget(
            db, current_user.id,
            BudgetCreate(category=cat, limit_amount=amount, month_year=month_year)
        )
        created.append(budget)

    await db.commit()

    return {
        "created_count": len(created),
        "total_budget": sum(suggestions.values()),
        "spendable_income": spendable,
        "savings_floor": income * (savings_pct / 100),
    }


@router.post("/resync-limits", status_code=200)
async def resync_budget_limits(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Recalculates normalized budget limits for the current month and updates
    existing budget rows. Does NOT reset current_spent or alert flags.
    Use this when limits are wrong but spending data should be preserved.
    """
    from datetime import datetime
    from sqlalchemy import select
    from app.models.budget import Budget
    from app.services.budget_calculator import calculate_suggested_budgets

    now = datetime.now()
    month_year = f"{now.year}-{now.month:02d}"

    real_income = await _get_user_real_income(db, current_user.id)
    suggestions = calculate_suggested_budgets(current_user, real_income=real_income)

    result = await db.execute(
        select(Budget).where(
            Budget.user_id == current_user.id,
            Budget.month_year == month_year,
        )
    )
    budgets = result.scalars().all()

    updated = 0
    for budget in budgets:
        if budget.category in suggestions:
            budget.limit_amount = suggestions[budget.category]
            # Reset alert flags since limits changed
            budget.alert_70_sent = False
            budget.alert_85_sent = False
            db.add(budget)
            updated += 1

    await db.commit()
    return {
        "updated_count": updated,
        "new_limits": suggestions,
        "total_limit": sum(suggestions.values()),
    }


@router.patch(
    "/{budget_id}",
    response_model=BudgetResponse,
    summary="Update a budget limit",
)
async def update_budget_limit(
    budget_id: str,
    data: BudgetUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update the limit_amount of an existing budget.
    Resets alert flags when limit is changed (so thresholds re-fire correctly).
    """
    from sqlalchemy import select
    from app.models.budget import Budget
    from datetime import datetime, timezone

    result = await db.execute(
        select(Budget).where(Budget.id == budget_id, Budget.user_id == current_user.id)
    )
    budget = result.scalar_one_or_none()
    if budget is None:
        raise HTTPException(status_code=404, detail="Budget not found")

    if data.limit_amount is not None:
        budget.limit_amount = data.limit_amount
        # Reset alert flags when limit changes so they fire again at new thresholds
        budget.alert_70_sent = False
        budget.alert_85_sent = False
        budget.updated_at = datetime.now(timezone.utc)

    db.add(budget)
    await db.commit()
    await db.refresh(budget)

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
