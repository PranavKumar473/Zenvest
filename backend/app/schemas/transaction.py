from typing import Optional
"""
Transaction request/response schemas.
"""

from datetime import datetime
from pydantic import BaseModel, Field


class TransactionCreate(BaseModel):
    """Create a new transaction."""
    vendor: str = Field(..., min_length=1, max_length=200, examples=["Swiggy"])
    amount: float = Field(..., gt=0, examples=[450.00])
    category: str = Field(..., examples=["food"])
    description: Optional[str] = Field(None, max_length=500)
    source: str = Field(default="manual", examples=["manual"])
    is_debit: bool = Field(default=True)
    timestamp: Optional[datetime] = Field(
        None, description="Transaction time; defaults to now"
    )


class TransactionResponse(BaseModel):
    """Single transaction response."""
    id: str
    user_id: str
    vendor: str
    amount: float
    category: str
    description: Optional[str] = None
    source: str
    is_debit: bool
    timestamp: datetime
    created_at: datetime

    model_config = {"from_attributes": True}


class TransactionListResponse(BaseModel):
    """Paginated transaction list response."""
    transactions: list[TransactionResponse]
    total_count: int
    page: int
    page_size: int
    has_next: bool


class TransactionBulkCreate(BaseModel):
    """Bulk import transactions from SMS parse."""
    transactions: list[TransactionCreate]


class TransactionBulkResponse(BaseModel):
    created_count: int
    skipped_duplicates: int
    transaction_ids: list[str]


class CategoryBreakdown(BaseModel):
    category: str
    display_name: str
    total_amount: float
    percentage: float
    transaction_count: int


class TransactionSummaryResponse(BaseModel):
    month: str
    total_debits: float
    total_credits: float
    net: float
    transaction_count: int
    debit_count: int
    credit_count: int
    category_breakdown: list[CategoryBreakdown]  # debit transactions only, sorted by amount desc


class EncryptedPayload(BaseModel):
    """AES-256-GCM encrypted data envelope."""
    iv: str = Field(..., description="Base64-encoded 12-byte nonce")
    ciphertext: str = Field(..., description="Base64-encoded ciphertext")
    tag: str = Field(..., description="Base64-encoded 16-byte GCM auth tag")


class TransactionSyncCreate(BaseModel):
    """
    Real-time transaction sync from notification listener.
    The payload field contains AES-256-GCM encrypted transaction data.
    """
    payload: EncryptedPayload
    source_app: str = Field(..., examples=["phonepe", "gpay", "paytm"])
    device_id: Optional[str] = Field(None, description="Device identifier for audit")


class TransactionSyncResponse(BaseModel):
    """Response from a real-time sync request."""
    success: bool
    transaction_id: Optional[str] = None
    message: str


