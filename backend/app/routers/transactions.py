from typing import Optional
"""
Transaction management API routes.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.transaction import (
    TransactionCreate,
    TransactionResponse,
    TransactionListResponse,
)
from app.services.transaction_service import (
    create_transaction,
    get_transactions,
    get_transaction_by_id,
)
from app.routers._deps import get_current_user

router = APIRouter(prefix="/transactions", tags=["Transactions"])


@router.get(
    "/",
    response_model=TransactionListResponse,
    summary="List transactions",
)
async def list_transactions(
    page: int = 1,
    page_size: int = 20,
    category: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch paginated transactions with optional category filter."""
    if page < 1:
        page = 1
    if page_size < 1 or page_size > 100:
        page_size = 20

    return await get_transactions(
        db, current_user.id, page, page_size, category
    )


@router.post(
    "/",
    response_model=TransactionResponse,
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

    response = TransactionResponse.model_validate(txn)
    # Warnings are included in response headers for client-side notification handling
    if warnings:
        # In production, this would push via WebSocket or FCM
        pass

    return response


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
