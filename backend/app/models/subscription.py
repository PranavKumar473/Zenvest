"""
Subscription model.
Tracks the recurring monthly consultation-fee engagement an investor sets
up with an advisor via Razorpay Subscriptions (or the mock billing provider
in local development).
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True,
        default=lambda: str(uuid.uuid4()), index=True
    )
    investor_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True
    )
    advisor_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False, index=True
    )
    amount_monthly: Mapped[float] = mapped_column(
        Numeric(12, 2), nullable=False
    )
    provider: Mapped[str] = mapped_column(
        String(20), nullable=False, default="mock", server_default="mock"
    )
    # "mock" | "razorpay"

    provider_plan_id: Mapped[str] = mapped_column(String(64), nullable=False)
    provider_subscription_id: Mapped[str] = mapped_column(
        String(64), nullable=False, index=True
    )

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="created", server_default="created"
    )
    # "created" | "active" | "past_due" | "cancelled" | "completed"

    current_period_end: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    investor = relationship("User", foreign_keys=[investor_id])
    advisor = relationship("User", foreign_keys=[advisor_id])

    def __repr__(self) -> str:
        return f"<Subscription(id={self.id}, advisor={self.advisor_id}, status={self.status})>"
