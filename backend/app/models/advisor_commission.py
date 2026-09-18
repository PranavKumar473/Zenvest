"""
Internal commission-split ledger.
One row per human-advisor-guided investment, decoupled from the investor-
facing Portfolio holding — lets finance track/approve/pay advisor payouts
without touching the investment record itself. Created only when
InvestmentConfirmation.advisor_source == "human".
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class AdvisorCommission(Base):
    __tablename__ = "advisor_commissions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    advisor_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    # Nullable: a human advisor may be named without matching a platform account.

    investor_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    investment_confirmation_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("investment_confirmations.id", ondelete="SET NULL"), nullable=True
    )
    portfolio_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("portfolios.id", ondelete="SET NULL"), nullable=True
    )

    advisor_name: Mapped[str] = mapped_column(String(200), nullable=False)
    advisor_euin: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    scheme_name: Mapped[str] = mapped_column(String(200), nullable=False)
    invested_amount: Mapped[float] = mapped_column(Numeric(14, 2), nullable=False)

    commission_rate: Mapped[Optional[float]] = mapped_column(Numeric(6, 4), nullable=True)
    # Fraction (e.g. 0.0075 = 0.75%). Null until finance assigns a payout policy.

    commission_amount: Mapped[Optional[float]] = mapped_column(Numeric(14, 2), nullable=True)
    # invested_amount * commission_rate, computed once a rate is assigned.

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending", server_default="pending"
    )
    # "pending" (rate not yet assigned) | "approved" | "paid"

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    advisor = relationship("User", foreign_keys=[advisor_id])
    investor = relationship("User", foreign_keys=[investor_id])

    def __repr__(self) -> str:
        return (
            f"<AdvisorCommission(advisor={self.advisor_name}, "
            f"amount={self.invested_amount}, status={self.status})>"
        )
