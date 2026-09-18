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

    # --- Smart Investment Routing (hidden corporate ARN + EUIN attribution) ---
    advisor_source: Mapped[str] = mapped_column(
        String(10), nullable=False, default="robo", server_default="robo")
    # "robo" | "human" — captured via the "Who guided your investment?" modal.

    advisor_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("users.id"), nullable=True)
    # FK to the advisor user, when the human advisor is a matched platform user.

    advisor_name: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    # Denormalized name capture — set even if advisor_id can't be resolved
    # (e.g. investor typed a name that doesn't match a platform account).

    advisor_euin: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # The advisor's EUIN as captured at investment time, for commission accounting.

    execution_arn: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    # Snapshot of the corporate ARN this investment was registered under.

    user = relationship("User", foreign_keys=[user_id])
    advisor = relationship("User", foreign_keys=[advisor_id])
