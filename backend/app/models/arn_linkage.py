"""
ARN/INA Linkage model.
Tracks when an investor formally attaches an advisor's regulatory
identifier to their investments:
  - ARN (AMFI Registration Number): mutual fund execution/distribution.
  - INA (SEBI RIA registration number, stored as User.sebi_registration_number):
    fee-only investment advice with no execution.
Once linked, the advisor unlocks read-only visibility into that investor's
portfolio (see arn_linkage.py router / my-investors endpoint).
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class ArnLinkage(Base):
    __tablename__ = "arn_linkages"

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
    linkage_type: Mapped[str] = mapped_column(
        String(10), nullable=False, default="ARN", server_default="ARN"
    )
    # "ARN" (mutual fund execution) | "INA" (fee-only advice, no execution)

    arn_number: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # Set when linkage_type == "ARN" — the advisor's AMFI ARN number

    ina_number: Mapped[Optional[str]] = mapped_column(
        String(30), nullable=True
    )
    # Set when linkage_type == "INA" — the advisor's SEBI RIA registration number

    linked_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )

    # Relationships
    investor = relationship("User", foreign_keys=[investor_id])
    advisor = relationship("User", foreign_keys=[advisor_id])

    @property
    def regulatory_number(self) -> Optional[str]:
        return self.arn_number if self.linkage_type == "ARN" else self.ina_number

    def __repr__(self) -> str:
        return (
            f"<ArnLinkage(investor={self.investor_id}, advisor={self.advisor_id}, "
            f"type={self.linkage_type}, number={self.regulatory_number})>"
        )
