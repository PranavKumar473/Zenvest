"""
Budget ORM model.
Tracks category-wise budget limits and spending for each month,
with alert threshold tracking for notification idempotency.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Numeric, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Budget(Base):
    __tablename__ = "budgets"

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
    category: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )  # "food", "bills", "shopping", "entertainment", "transport", "health"
    limit_amount: Mapped[float] = mapped_column(
        Numeric(12, 2), nullable=False
    )
    current_spent: Mapped[float] = mapped_column(
        Numeric(12, 2), default=0.00, nullable=False
    )
    month_year: Mapped[str] = mapped_column(
        String(7), nullable=False, index=True
    )  # "2026-06" format
    alert_70_sent: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    alert_85_sent: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
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
    user = relationship("User", back_populates="budgets")

    @property
    def spent_percentage(self) -> float:
        """Calculate percentage of budget spent."""
        if self.limit_amount and float(self.limit_amount) > 0:
            return (float(self.current_spent) / float(self.limit_amount)) * 100
        return 0.0

    @property
    def remaining(self) -> float:
        """Calculate remaining budget amount."""
        return float(self.limit_amount) - float(self.current_spent)

    @property
    def threshold_status(self) -> str:
        """Return threshold status: 'safe', 'warning', or 'danger'."""
        pct = self.spent_percentage
        if pct >= 85:
            return "danger"
        elif pct >= 70:
            return "warning"
        return "safe"

    def __repr__(self) -> str:
        return f"<Budget(id={self.id}, category={self.category}, {self.spent_percentage:.0f}%)>"
