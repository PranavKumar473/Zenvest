from typing import Optional
"""
User ORM model.
Stores authentication credentials, profile data, and risk assessment results.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Boolean, DateTime, JSON, Integer, Numeric
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
    phone_number: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )  # User's phone number for SMS parsing/mapping
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
    
    # Advisor and user type fields
    user_type: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="user",
        server_default="user",
        index=True,
    )
    # "user" or "advisor"

    arn_number: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # AMFI ARN number — only for advisors. Format: ARN-XXXXX
    # NOTE: investments executed through the platform's "Invest" flow always
    # register under the platform's own CORPORATE_ARN (app/config.py), never
    # an individual advisor's personal ARN — see app/services/investment_service.py.
    # This field is informational (shown on the advisor's public profile for
    # advisors who are independently AMFI-registered) and isn't used for
    # fund-house execution routing.

    euin: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # Employee Unique Identification Number — the AMFI-mandated identifier
    # for an individual advisor operating under a corporate ARN. Used to
    # attribute a platform-routed investment to the human advisor who
    # guided it, for internal commission-split accounting, while the
    # fund-house-facing registration stays under CORPORATE_ARN.

    arn_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )
    # True after admin verification (manual process for MVP)

    advisor_name: Mapped[Optional[str]] = mapped_column(
        String(200), nullable=True
    )
    # Full legal name as on ARN card

    advisor_license_image_url: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True
    )
    # Uploaded image URL of physical ARN card (stored in local /uploads/ for MVP)

    # --- Enhanced Advisor Profile Fields ---
    gst_number: Mapped[Optional[str]] = mapped_column(
        String(20), nullable=True
    )
    # GST registration number (optional — only if turnover > ₹20L)

    gst_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, server_default="false"
    )
    # True after GST portal API verification (kept in sync with gst_verification_status)

    gst_verification_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="unverified", server_default="unverified"
    )
    # "unverified" | "pending" | "verified" | "failed"

    gst_legal_name: Mapped[Optional[str]] = mapped_column(
        String(200), nullable=True
    )
    # Legal entity name returned by the GST Portal on successful verification

    pan_number: Mapped[Optional[str]] = mapped_column(
        String(10), nullable=True
    )
    # PAN card number (masked in API responses)

    address: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True
    )
    # {line1, line2, city, state, pincode}

    profile_image_url: Mapped[Optional[str]] = mapped_column(
        String(500), nullable=True
    )
    # Uploaded profile picture path

    sebi_registration_number: Mapped[Optional[str]] = mapped_column(
        String(30), nullable=True
    )
    # SEBI RIA registration number (if applicable)

    consultation_fee_monthly: Mapped[Optional[float]] = mapped_column(
        Numeric(12, 2), nullable=True
    )
    # Monthly consultation charges in INR

    bio: Mapped[Optional[str]] = mapped_column(
        String(2000), nullable=True
    )
    # Advisor bio / about text

    specializations: Mapped[Optional[dict]] = mapped_column(
        JSON, nullable=True
    )
    # List of specialization areas, e.g. ["Mutual Funds", "Tax Planning"]

    experience_years: Mapped[Optional[int]] = mapped_column(
        Integer, nullable=True
    )
    # Years of professional experience

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
        "Portfolio",
        back_populates="user",
        cascade="all, delete-orphan",
        foreign_keys="[Portfolio.user_id]",
    )

    @property
    def ina_number(self) -> Optional[str]:
        """Alias of sebi_registration_number — the INA used for fee-only advice."""
        return self.sebi_registration_number

    def __repr__(self) -> str:
        return f"<User(id={self.id}, email={self.email})>"
