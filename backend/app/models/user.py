from typing import Optional
"""
User ORM model.
Stores authentication credentials, profile data, and risk assessment results.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Boolean, DateTime, JSON, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(36),
        primary_key=True,
        default=lambda: str(uuid.uuid4()),
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False, index=True
    )
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    income_bracket: Mapped[Optional[str]] = mapped_column(
        String(50), nullable=True
    )  # e.g., "0-5L", "5-10L", "10-25L", "25L+"
    age_group: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )  # e.g., "18-25", "26-35", "36-45", "46-60", "60+"
    risk_profile: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True
    )  # {"score": 72, "level": "Aggressive", "answers": [...]}
    biometric_enabled: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    biometric_public_key: Mapped[Optional[str]] = mapped_column(
        String(1024), nullable=True
    )
    onboarding_completed: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    goals: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True
    )  # ["retirement", "home", "education", ...]
    refresh_token_hash: Mapped[Optional[str]] = mapped_column(
        String(255), nullable=True
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
    budgets = relationship("Budget", back_populates="user", cascade="all, delete-orphan")
    transactions = relationship(
        "Transaction", back_populates="user", cascade="all, delete-orphan"
    )
    portfolios = relationship(
        "Portfolio", back_populates="user", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<User(id={self.id}, email={self.email})>"
