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
