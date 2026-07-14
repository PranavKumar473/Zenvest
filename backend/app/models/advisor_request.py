"""
Advisor Request model.
Tracks the investor → advisor request/approval workflow.
An investor must request an advisor before they can call/chat.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, JSON, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class AdvisorRequest(Base):
    __tablename__ = "advisor_requests"

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
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending",
        server_default="pending"
    )
    # "pending" | "accepted" | "rejected"

    investor_risk_profile: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True
    )
    # Snapshot of investor's risk profile at request time

    message: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True
    )
    # Investor's introductory message

    advisor_response: Mapped[Optional[str]] = mapped_column(
        Text, nullable=True
    )
    # Advisor's acceptance/rejection note

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    responded_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Relationships
    investor = relationship("User", foreign_keys=[investor_id])
    advisor = relationship("User", foreign_keys=[advisor_id])
    messages = relationship("ChatMessage", back_populates="request",
                           cascade="all, delete-orphan")
    call_sessions = relationship("CallSession", back_populates="request",
                                cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<AdvisorRequest(id={self.id}, investor={self.investor_id}, advisor={self.advisor_id}, status={self.status})>"
