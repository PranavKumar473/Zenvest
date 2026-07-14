"""
Authentication request/response schemas.
"""

from pydantic import BaseModel, EmailStr, Field, model_validator
from typing import Optional, Literal


class RegisterRequest(BaseModel):
    """User or Advisor registration payload."""
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    user_type: Literal["user", "advisor"] = Field(
        default="user",
        description="'user' for regular investors, 'advisor' for AMFI-registered advisors"
    )
    # Advisor-only fields — required when user_type == "advisor"
    arn_number: Optional[str] = Field(
        None,
        pattern=r"^ARN-\d{4,6}$",
        description="AMFI ARN number in format ARN-XXXXX. Required for advisors.",
        examples=["ARN-12345"]
    )
    advisor_name: Optional[str] = Field(
        None,
        min_length=2,
        max_length=200,
        description="Full legal name as printed on ARN card. Required for advisors."
    )

    # Additional advisor fields
    gst_number: Optional[str] = Field(None, description="GST registration number (optional)")
    pan_number: Optional[str] = Field(None, description="PAN card number (required for advisors)")
    address: Optional[dict] = Field(None, description="Physical address {line1, line2, city, state, pincode}")
    sebi_registration_number: Optional[str] = Field(None, description="SEBI RIA registration number (optional)")
    bio: Optional[str] = Field(None, description="Short bio/about text")
    specializations: Optional[list[str]] = Field(None, description="Advisory specializations")
    experience_years: Optional[int] = Field(None, description="Years of professional experience")
    consultation_fee_monthly: Optional[float] = Field(None, description="Monthly consultation fee in INR")

    @model_validator(mode='after')
    def validate_advisor_fields(self):
        if self.user_type == "advisor":
            if not self.arn_number:
                raise ValueError("ARN number is required for advisor registration")
            if not self.advisor_name:
                raise ValueError("Legal name (as on ARN card) is required for advisor registration")
            # PAN, address, GST, and SEBI/INA are collected in the post-registration
            # advisor verification flow (see /advisors/me/complete-onboarding),
            # not at initial sign-up — mirrors the investor onboarding split.
        return self


class LoginRequest(BaseModel):
    """User login payload."""
    email: EmailStr = Field(..., examples=["pranav@example.com"])
    password: str = Field(..., examples=["SecurePass123"])


class TokenResponse(BaseModel):
    """JWT token pair response."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Access token expiry in seconds")


class RefreshRequest(BaseModel):
    """Token refresh payload."""
    refresh_token: str


class BiometricChallengeResponse(BaseModel):
    """Biometric authentication challenge."""
    challenge: str = Field(description="Random challenge string to sign")
    expires_at: str = Field(description="ISO 8601 timestamp when challenge expires")


class BiometricVerifyRequest(BaseModel):
    """Biometric verification payload."""
    user_id: str
    challenge: str
    signature: str = Field(description="Challenge signed with device private key")
