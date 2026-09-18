from typing import Optional
"""
Transaction ORM model.
Records individual financial transactions with categorization and source tracking.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Numeric, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[str] = mapped_column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )
    user_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    vendor: Mapped[str] = mapped_column(String(200), nullable=False)
    amount: Mapped[float] = mapped_column(
        Numeric(12, 2), nullable=False
    )
    category: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )  # "food", "bills", "shopping", "entertainment", "transport", "health"
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    source: Mapped[str] = mapped_column(
        String(20), default="manual", nullable=False
    )  # "sms", "manual", "aa" (account_aggregator)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )
    is_debit: Mapped[bool] = mapped_column(default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    user = relationship("User", back_populates="transactions")

    def __repr__(self) -> str:
        return (
            f"<Transaction(id={self.id}, vendor={self.vendor}, "
            f"amount={self.amount}, category={self.category})>"
        )
