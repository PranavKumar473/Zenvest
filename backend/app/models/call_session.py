"""
Call Session model.
Tracks masked call sessions between investor and advisor.
Calls are only permitted after the advisor has accepted the request.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Integer, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class CallSession(Base):
    __tablename__ = "call_sessions"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True,
        default=lambda: str(uuid.uuid4()), index=True
    )
    request_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("advisor_requests.id", ondelete="CASCADE"),
        nullable=False, index=True
    )
    investor_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )
    advisor_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )
    masked_number: Mapped[str] = mapped_column(
        String(30), nullable=False
    )
    # Virtual masked phone number used for the session

    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="initiated",
        server_default="initiated"
    )
    # "initiated" | "ringing" | "connected" | "ended"

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    ended_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    duration_seconds: Mapped[int] = mapped_column(
        Integer, default=0, nullable=False
    )
    recording_url: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True
    )
    # Populated by the telephony provider's recording-status webhook once the
    # call ends (see routers/webhooks.py). Archived indefinitely for audit trail.

    provider: Mapped[str] = mapped_column(
        String(20), nullable=False, default="mock", server_default="mock"
    )
    # "mock" | "twilio" — which TelephonyProvider handled this session

    provider_call_sid: Mapped[Optional[str]] = mapped_column(
        String(64), nullable=True, index=True
    )
    # Twilio Call SID (or equivalent), used to match incoming webhook callbacks

    # Relationships
    request = relationship("AdvisorRequest", back_populates="call_sessions")
    investor = relationship("User", foreign_keys=[investor_id])
    advisor = relationship("User", foreign_keys=[advisor_id])

    def __repr__(self) -> str:
        return f"<CallSession(id={self.id}, status={self.status}, duration={self.duration_seconds}s)>"
