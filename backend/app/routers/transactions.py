from typing import Optional
"""
Transaction management API routes.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.transaction import (
    TransactionCreate,
    TransactionResponse,
    TransactionListResponse,
    TransactionBulkCreate,
    TransactionBulkResponse,
    TransactionSummaryResponse,
    TransactionSyncCreate,
    TransactionSyncResponse,
    TransactionWithWarningsResponse,
)
from app.services.transaction_service import (
    create_transaction,
    get_transactions,
    get_transaction_by_id,
    bulk_create_transactions,
    get_transaction_summary,
    create_synced_transaction,
)
from app.services.audit_service import log_event
from app.middleware.security import limiter
from app.routers._deps import get_current_user

router = APIRouter(prefix="/transactions", tags=["Transactions"])


@router.get(
    "",
    response_model=TransactionListResponse,
    summary="List transactions",
)
async def list_transactions(
    page: int = 1,
    page_size: int = 20,
    category: Optional[str] = None,
    is_debit: Optional[bool] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch paginated transactions with optional category and is_debit filter."""
    if page < 1:
        page = 1
    if page_size < 1 or page_size > 100:
        page_size = 20

    return await get_transactions(
        db, current_user.id, page, page_size, category, is_debit
    )


@router.post(
    "",
    response_model=TransactionWithWarningsResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record a transaction",
)
async def record_transaction(
    data: TransactionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Record a new transaction and update the corresponding budget.
    Returns the transaction and any budget warnings triggered.
    """
    txn, warnings = await create_transaction(db, current_user.id, data)

    return TransactionWithWarningsResponse(
        **TransactionResponse.model_validate(txn).model_dump(),
        warnings=[w.model_dump() for w in warnings],
    )


@router.post(
    "/bulk",
    response_model=TransactionBulkResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Bulk import transactions",
)
async def bulk_import_transactions(
    data: TransactionBulkCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Bulk import SMS-parsed transactions. Idempotent — deduplicates by amount+vendor+time."""
    return await bulk_create_transactions(db, current_user.id, data)


@router.get(
    "/summary",
    response_model=TransactionSummaryResponse,
    summary="Get transaction summary breakdown",
)
async def get_transaction_summary_route(
    month: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns total_debits, total_credits, category_breakdown (for debits only),
    and transaction_count for the given month (YYYY-MM). Defaults to current month.
    """
    return await get_transaction_summary(db, current_user.id, month)


@router.get(
    "/{transaction_id}",
    response_model=TransactionResponse,
    summary="Get a single transaction",
)
async def get_single_transaction(
    transaction_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch a specific transaction by ID."""
    txn = await get_transaction_by_id(db, current_user.id, transaction_id)
    if txn is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found",
        )
    return TransactionResponse.model_validate(txn)


@router.post(
    "/sync",
    response_model=TransactionSyncResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Sync real-time transaction from notification listener",
)
@limiter.limit("30/minute")
async def sync_transaction(
    request: Request,
    data: TransactionSyncCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Decrypt, validate, deduplicate, and record a transaction from notification listener.
    Strictly rate limited to prevent brute forcing or abuse.
    """
    response = await create_synced_transaction(db, current_user.id, data)

    # Audit log
    await log_event(
        db=db,
        event_type="transaction_sync",
        user_id=current_user.id,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        details={
            "success": response.success,
            "source_app": data.source_app,
            "device_id": data.device_id,
            "transaction_id": response.transaction_id,
            "message": response.message,
        }
    )

    if not response.success:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=response.message
        )

    return response
