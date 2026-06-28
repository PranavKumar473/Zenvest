"""
Authentication request/response schemas.
"""

from pydantic import BaseModel, EmailStr, Field


class RegisterRequest(BaseModel):
    """User registration payload."""
    name: str = Field(..., min_length=2, max_length=100, examples=["Pranav Kumar"])
    email: EmailStr = Field(..., examples=["pranav@example.com"])
    password: str = Field(
        ...,
        min_length=8,
        max_length=128,
        description="Minimum 8 characters with at least one uppercase, lowercase, and digit",
        examples=["SecurePass123"],
    )


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
