"""
Chat Message model.
Stores messages between investor and advisor within an accepted request.
All messages are recorded for compliance and dispute resolution.
"""
import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True,
        default=lambda: str(uuid.uuid4()), index=True
    )
    request_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("advisor_requests.id", ondelete="CASCADE"),
        nullable=False, index=True
    )
    sender_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )
    receiver_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )
    content: Mapped[str] = mapped_column(
        Text, nullable=False
    )
    message_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default="text",
        server_default="text"
    )
    # "text" | "system" | "call_log"

    is_read: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    request = relationship("AdvisorRequest", back_populates="messages")
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])

    def __repr__(self) -> str:
        return f"<ChatMessage(id={self.id}, sender={self.sender_id}, type={self.message_type})>"
