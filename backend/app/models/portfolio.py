from typing import Optional
"""
Portfolio ORM model.
Tracks investment holdings across asset types with performance metrics.
"""

import uuid
from datetime import datetime, timezone, date
from sqlalchemy import String, Numeric, Float, DateTime, Date, ForeignKey, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class Portfolio(Base):
    __tablename__ = "portfolios"

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
    asset_name: Mapped[str] = mapped_column(
        String(200), nullable=False
    )  # e.g., "HDFC Balanced Advantage Fund", "SBI FD 7.1%"
    asset_type: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )  # "mutual_fund", "fixed_deposit", "stocks", "gold", "bonds"
    current_value: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False
    )
    initial_investment: Mapped[float] = mapped_column(
        Numeric(14, 2), nullable=False
    )
    calculated_xirr: Mapped[Optional[float]] = mapped_column(
        Float, nullable=True
    )  # Annualized return using XIRR
    calculated_cagr: Mapped[Optional[float]] = mapped_column(
        Float, nullable=True
    )  # Compound Annual Growth Rate
    start_date: Mapped[date] = mapped_column(
        Date, nullable=False
    )
    # Historical value snapshots for charting: [{"date": "2026-01", "value": 105000}, ...]
    value_history: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    # Cash flow records for XIRR: [{"date": "2025-01-15", "amount": -50000}, ...]
    cash_flows: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    last_updated: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # --- Advisor ARN Linkage Fields ---
    advisor_arn: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # ARN number of the advisor through whom this investment was made

    investment_mode: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # "sip" | "lumpsum" | "other"

    advisor_id: Mapped[Optional[str]] = mapped_column(
        String(36), ForeignKey("users.id"), nullable=True
    )
    # FK to the advisor user who facilitated this investment

    # --- Smart Investment Routing (hidden corporate ARN + EUIN attribution) ---
    advisor_source: Mapped[str] = mapped_column(
        String(10), nullable=False, default="robo", server_default="robo"
    )
    # "robo" | "human" — who guided this investment (captured via the
    # "Who guided your investment?" modal). Distinct from advisor_id, which
    # may be null even when advisor_source == "human" if the advisor was
    # entered by name only and isn't a matched platform user.

    execution_arn: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # The ARN actually submitted to the fund house for this transaction —
    # always CORPORATE_ARN (app/config.py), regardless of advisor_source.
    # Never the individual advisor's personal arn_number. Null on rows
    # created before this field existed.

    advisor_euin: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # Snapshot of the human advisor's EUIN at the time of this investment,
    # for internal commission-split accounting (see AdvisorCommission).

    # Relationships
    user = relationship("User", back_populates="portfolios", foreign_keys=[user_id])

    @property
    def absolute_return(self) -> float:
        """Calculate absolute return in currency."""
        return float(self.current_value) - float(self.initial_investment)

    @property
    def return_percentage(self) -> float:
        """Calculate simple return percentage."""
        if float(self.initial_investment) > 0:
            return (self.absolute_return / float(self.initial_investment)) * 100
        return 0.0

    def __repr__(self) -> str:
        return (
            f"<Portfolio(id={self.id}, asset={self.asset_name}, "
            f"type={self.asset_type}, value={self.current_value})>"
        )
