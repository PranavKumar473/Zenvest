from typing import Optional
"""
User request/response schemas.
"""

from datetime import datetime
from pydantic import BaseModel, Field


class UserResponse(BaseModel):
    """User profile response."""
    id: str
    name: str
    email: str
    income_bracket: Optional[str] = None
    age_group: Optional[str] = None
    phone_number: Optional[str] = None
    risk_profile: Optional[dict] = None
    biometric_enabled: bool = False
    onboarding_completed: bool = False
    goals: Optional[list[str]] = None
    user_type: str = "user"
    arn_number: Optional[str] = None
    arn_verified: bool = False
    advisor_name: Optional[str] = None
    advisor_license_image_url: Optional[str] = None
    # Enhanced advisor fields
    gst_number: Optional[str] = None
    gst_verified: bool = False
    gst_verification_status: str = "unverified"
    gst_legal_name: Optional[str] = None
    pan_number: Optional[str] = None
    address: Optional[dict] = None
    profile_image_url: Optional[str] = None
    sebi_registration_number: Optional[str] = None
    ina_number: Optional[str] = None  # alias of sebi_registration_number — the SEBI INA used for fee-only advice
    consultation_fee_monthly: Optional[float] = None
    bio: Optional[str] = None
    specializations: Optional[list[str]] = None
    experience_years: Optional[int] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class AdvisorPublicResponse(BaseModel):
    """
    Fully verified advisor profile visible to investors, per SEBI/GST
    disclosure requirements. PAN and phone are masked for privacy; GST and
    SEBI registration (INA) are shown in full since they are public
    regulatory identifiers.
    """
    id: str
    name: str
    email: str
    phone_number: Optional[str] = None  # masked for privacy
    profile_image_url: Optional[str] = None
    address: Optional[dict] = None
    pan_masked: Optional[str] = None  # e.g. "ABCDE****F"

    # Mutual fund execution — AMFI ARN
    arn_number: Optional[str] = None
    arn_verified: bool = False

    # Fee-only advice — SEBI RIA registration (INA number)
    sebi_registration_number: Optional[str] = None
    ina_number: Optional[str] = None  # alias of sebi_registration_number, shown explicitly per SEBI labeling

    # GST
    gst_number: Optional[str] = None
    gst_verified: bool = False
    gst_verification_status: str = "unverified"

    consultation_fee_monthly: Optional[float] = None
    bio: Optional[str] = None
    specializations: Optional[list[str]] = None
    experience_years: Optional[int] = None
    rating: float = 5.0
    charges: Optional[str] = None

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    """User profile update payload."""
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    income_bracket: Optional[str] = None
    age_group: Optional[str] = None
    phone_number: Optional[str] = None
    biometric_enabled: Optional[bool] = None
    # Advisor-specific update fields
    bio: Optional[str] = None
    specializations: Optional[list[str]] = None
    experience_years: Optional[int] = None
    consultation_fee_monthly: Optional[float] = None
    gst_number: Optional[str] = None
    pan_number: Optional[str] = None
    address: Optional[dict] = None
    sebi_registration_number: Optional[str] = None
    profile_image_url: Optional[str] = None


class OnboardingRequest(BaseModel):
    """Onboarding completion payload."""
    age_group: str = Field(
        ...,
        description="User age bracket",
        examples=["26-35"],
    )
    income_bracket: str = Field(
        ...,
        description="Annual income range",
        examples=["10-25L"],
    )
    goals: Optional[list[str]] = Field(
        default_factory=list,
        description="Financial goals",
        examples=[["retirement", "home_purchase", "emergency_fund"]],
    )


class RiskAssessmentRequest(BaseModel):
    """Risk assessment submission payload."""
    answers: list[int] = Field(
        ...,
        min_length=10,
        max_length=10,
        description="List of 10 answers (0-3 score each)",
        examples=[[2, 3, 1, 2, 3, 2, 1, 3, 2, 2]],
    )


class RiskProfileResponse(BaseModel):
    """Calculated risk profile response."""
    score: int = Field(description="Total risk score (0-100)")
    level: str = Field(description="Risk level label")
    description: str = Field(description="Human-readable risk description")
    recommended_allocation: dict = Field(
        description="Recommended asset allocation percentages"
    )
