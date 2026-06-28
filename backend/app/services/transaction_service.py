from typing import Optional
"""
Transaction service.
Handles transaction CRUD with pagination and budget integration.
"""

from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

from app.models.transaction import Transaction
from app.schemas.transaction import TransactionCreate, TransactionListResponse, TransactionResponse
from app.services.budget_service import add_transaction_to_budget


async def create_transaction(
    db: AsyncSession, user_id: str, data: TransactionCreate
) -> tuple[Transaction, list]:
    """
    Create a new transaction and update the corresponding budget.
    Returns the transaction and any budget warnings triggered.
    """
    txn = Transaction(
        user_id=user_id,
        vendor=data.vendor,
        amount=data.amount,
        category=data.category.lower(),
        description=data.description,
        source=data.source,
        is_debit=data.is_debit,
        timestamp=data.timestamp or datetime.now(timezone.utc),
    )
    db.add(txn)
    await db.flush()

    # Update budget if this is a debit transaction
    warnings = []
    if data.is_debit:
        month_year = txn.timestamp.strftime("%Y-%m")
        warnings = await add_transaction_to_budget(
            db, user_id, data.category, data.amount, month_year
        )

    await db.refresh(txn)
    return txn, warnings


async def get_transactions(
    db: AsyncSession,
    user_id: str,
    page: int = 1,
    page_size: int = 20,
    category: Optional[str] = None,
) -> TransactionListResponse:
    """
    Fetch paginated transactions for a user.
    Supports filtering by category. Ordered by timestamp descending.
    """
    # Base query
    base_query = select(Transaction).where(Transaction.user_id == user_id)

    if category:
        base_query = base_query.where(Transaction.category == category.lower())

    # Count total
    count_query = select(func.count()).select_from(base_query.subquery())
    total_result = await db.execute(count_query)
    total_count = total_result.scalar() or 0

    # Fetch page
    offset = (page - 1) * page_size
    data_query = (
        base_query
        .order_by(desc(Transaction.timestamp))
        .offset(offset)
        .limit(page_size)
    )
    result = await db.execute(data_query)
    transactions = list(result.scalars().all())

    return TransactionListResponse(
        transactions=[
            TransactionResponse.model_validate(t) for t in transactions
        ],
        total_count=total_count,
        page=page,
        page_size=page_size,
        has_next=(offset + page_size) < total_count,
    )


async def get_transaction_by_id(
    db: AsyncSession, user_id: str, transaction_id: str
) -> Optional[Transaction]:
    """Fetch a single transaction by ID, scoped to user."""
    result = await db.execute(
        select(Transaction).where(
            Transaction.id == transaction_id,
            Transaction.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()
