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
    risk_profile: Optional[dict] = None
    biometric_enabled: bool = False
    onboarding_completed: bool = False
    goals: Optional[list[str]] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    """User profile update payload."""
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    income_bracket: Optional[str] = None
    age_group: Optional[str] = None
    biometric_enabled: Optional[bool] = None


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
    goals: list[str] = Field(
        ...,
        min_length=1,
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
