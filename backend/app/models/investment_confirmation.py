"""
Tracks user's confirmed investments from the advisor screen.
Each confirmed investment auto-creates a Portfolio entry.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Numeric, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base

class InvestmentConfirmation(Base):
    __tablename__ = "investment_confirmations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True,
                                     default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String(36),
                                          ForeignKey("users.id", ondelete="CASCADE"),
                                          nullable=False, index=True)
    asset_type: Mapped[str] = mapped_column(String(50), nullable=False)
    scheme_name: Mapped[str] = mapped_column(String(200), nullable=False)
    suggested_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    actual_amount: Mapped[float] = mapped_column(Numeric(12, 2), nullable=False)
    # actual_amount: user types this if they invested a different amount
    confirmed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    confirmed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    user = relationship("User")
