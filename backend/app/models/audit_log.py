"""
AuditLog ORM model.
Records all security-relevant events for compliance and forensics.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
    )
    user_id: Mapped[str] = mapped_column(
        String(36), nullable=True, index=True
    )
    event_type: Mapped[str] = mapped_column(
        String(50), nullable=False, index=True
    )
    # e.g. "transaction_sync", "bulk_import", "login_success",
    #      "login_failure", "token_refresh", "permission_grant"
    ip_address: Mapped[str] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str] = mapped_column(Text, nullable=True)
    details: Mapped[dict] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
        index=True,
    )

    def __repr__(self) -> str:
        return (
            f"<AuditLog(id={self.id}, event={self.event_type}, "
            f"user={self.user_id})>"
        )
