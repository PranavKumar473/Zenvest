from typing import Optional
"""
Transaction service.
Handles transaction CRUD with pagination and budget integration.
"""

from datetime import datetime, timezone, timedelta
import calendar
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc

from app.models.transaction import Transaction
from app.schemas.transaction import (
    TransactionCreate,
    TransactionListResponse,
    TransactionResponse,
    TransactionBulkCreate,
    TransactionBulkResponse,
    CategoryBreakdown,
    TransactionSummaryResponse,
    TransactionSyncCreate,
    TransactionSyncResponse,
)
from app.utils.crypto_utils import decrypt_payload
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
    is_debit: Optional[bool] = None,
) -> TransactionListResponse:
    """
    Fetch paginated transactions for a user.
    Supports filtering by category. Ordered by timestamp descending.
    """
    # Base query
    base_query = select(Transaction).where(Transaction.user_id == user_id)

    if category:
        base_query = base_query.where(Transaction.category == category.lower())

    if is_debit is not None:
        base_query = base_query.where(Transaction.is_debit == is_debit)

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


async def bulk_create_transactions(
    db: AsyncSession, user_id: str, transactions_data: TransactionBulkCreate
) -> TransactionBulkResponse:
    """
    Bulk import transactions from SMS parse.
    Deduplicates based on user_id, amount, vendor, and timestamp (within 60s window).
    """
    created_count = 0
    skipped_duplicates = 0
    transaction_ids = []

    for txn_data in transactions_data.transactions:
        # Check for duplicates within a 60-second window
        timestamp = txn_data.timestamp or datetime.now(timezone.utc)
        start_time = timestamp - timedelta(seconds=60)
        end_time = timestamp + timedelta(seconds=60)

        # Query existing transaction
        stmt = select(Transaction).where(
            Transaction.user_id == user_id,
            Transaction.amount == txn_data.amount,
            Transaction.vendor == txn_data.vendor,
            Transaction.timestamp.between(start_time, end_time)
        )
        result = await db.execute(stmt)
        existing = result.scalar_one_or_none()

        if existing:
            skipped_duplicates += 1
        else:
            # Create transaction using existing service function
            txn, _ = await create_transaction(db, user_id, txn_data)
            created_count += 1
            transaction_ids.append(txn.id)

    return TransactionBulkResponse(
        created_count=created_count,
        skipped_duplicates=skipped_duplicates,
        transaction_ids=transaction_ids
    )


async def get_transaction_summary(
    db: AsyncSession, user_id: str, month: Optional[str] = None
) -> TransactionSummaryResponse:
    """
    Calculate summary totals and category breakdown for a given month.
    """
    # Parse month (YYYY-MM)
    if month:
        try:
            year, month_num = map(int, month.split("-"))
        except ValueError:
            now = datetime.now(timezone.utc)
            year, month_num = now.year, now.month
    else:
        now = datetime.now(timezone.utc)
        year, month_num = now.year, now.month

    # Calculate date range
    _, last_day = calendar.monthrange(year, month_num)
    start_date = datetime(year, month_num, 1, 0, 0, 0, tzinfo=timezone.utc)
    end_date = datetime(year, month_num, last_day, 23, 59, 59, 999999, tzinfo=timezone.utc)

    # 1. Total debits, credits and counts
    summary_stmt = select(
        func.sum(Transaction.amount).filter(Transaction.is_debit == True).label("total_debits"),
        func.sum(Transaction.amount).filter(Transaction.is_debit == False).label("total_credits"),
        func.count(Transaction.id).label("total_count"),
        func.count(Transaction.id).filter(Transaction.is_debit == True).label("debit_count"),
        func.count(Transaction.id).filter(Transaction.is_debit == False).label("credit_count")
    ).where(
        Transaction.user_id == user_id,
        Transaction.timestamp >= start_date,
        Transaction.timestamp <= end_date
    )
    res = await db.execute(summary_stmt)
    row = res.fetchone()

    total_debits = float(row.total_debits or 0) if row else 0.0
    total_credits = float(row.total_credits or 0) if row else 0.0
    transaction_count = int(row.total_count or 0) if row else 0
    debit_count = int(row.debit_count or 0) if row else 0
    credit_count = int(row.credit_count or 0) if row else 0

    net = total_credits - total_debits

    # 2. Category breakdown (debits only)
    category_stmt = select(
        Transaction.category,
        func.sum(Transaction.amount).label("total_amount"),
        func.count(Transaction.id).label("txn_count")
    ).where(
        Transaction.user_id == user_id,
        Transaction.is_debit == True,
        Transaction.timestamp >= start_date,
        Transaction.timestamp <= end_date
    ).group_by(Transaction.category).order_by(desc("total_amount"))

    res = await db.execute(category_stmt)
    categories = res.all()

    category_map = {
        "food": "Food & Dining",
        "bills": "Bills & Utilities",
        "shopping": "Shopping",
        "entertainment": "Entertainment",
        "transport": "Transport",
        "health": "Health & Fitness",
        "other": "Other"
    }

    category_breakdown = []
    for cat_name, total_amt, txn_count in categories:
        total_amt = float(total_amt or 0)
        percentage = (total_amt / total_debits * 100.0) if total_debits > 0 else 0.0
        disp_name = category_map.get(cat_name, cat_name.title())
        category_breakdown.append(CategoryBreakdown(
            category=cat_name,
            display_name=disp_name,
            total_amount=total_amt,
            percentage=round(percentage, 2),
            transaction_count=int(txn_count)
        ))

    # Format YYYY-MM
    month_str = f"{year:04d}-{month_num:02d}"

    return TransactionSummaryResponse(
        month=month_str,
        total_debits=total_debits,
        total_credits=total_credits,
        net=net,
        transaction_count=transaction_count,
        debit_count=debit_count,
        credit_count=credit_count,
        category_breakdown=category_breakdown
    )


async def create_synced_transaction(
    db: AsyncSession, user_id: str, sync_data: TransactionSyncCreate
) -> TransactionSyncResponse:
    """
    Create a transaction from an encrypted notification sync payload.
    Decrypts the payload, validates, deduplicates, and stores.
    """
    # Decrypt the AES-256-GCM payload
    decrypted = decrypt_payload(sync_data.payload.model_dump())
    if decrypted is None:
        return TransactionSyncResponse(
            success=False,
            message="Decryption failed — payload may be tampered or key mismatch",
        )

    # Validate required fields from decrypted data
    try:
        vendor = decrypted.get("vendor", "Unknown")
        amount = float(decrypted.get("amount", 0))
        is_debit = decrypted.get("is_debit", True)
        category = decrypted.get("category", "other")
        description = decrypted.get("description")
        timestamp_str = decrypted.get("timestamp")

        if amount <= 0:
            return TransactionSyncResponse(
                success=False,
                message="Invalid amount in payload",
            )

        timestamp = (
            datetime.fromisoformat(timestamp_str)
            if timestamp_str
            else datetime.now(timezone.utc)
        )
    except (ValueError, TypeError) as e:
        return TransactionSyncResponse(
            success=False,
            message=f"Invalid payload data: {str(e)}",
        )

    # Deduplicate: check for same user, amount, vendor within 60s window
    start_time = timestamp - timedelta(seconds=60)
    end_time = timestamp + timedelta(seconds=60)
    stmt = select(Transaction).where(
        Transaction.user_id == user_id,
        Transaction.amount == amount,
        Transaction.vendor == vendor,
        Transaction.timestamp.between(start_time, end_time),
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        return TransactionSyncResponse(
            success=True,
            transaction_id=existing.id,
            message="Duplicate transaction — already recorded",
        )

    # Create the transaction
    txn_data = TransactionCreate(
        vendor=vendor,
        amount=amount,
        category=category,
        description=description,
        source=sync_data.source_app,
        is_debit=is_debit,
        timestamp=timestamp,
    )
    txn, _ = await create_transaction(db, user_id, txn_data)

    return TransactionSyncResponse(
        success=True,
        transaction_id=txn.id,
        message="Transaction synced successfully",
    )
