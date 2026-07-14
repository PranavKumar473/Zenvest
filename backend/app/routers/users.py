"""
User management and onboarding API routes.
"""

import os
import shutil
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.user import (
    UserResponse,
    UserUpdate,
    OnboardingRequest,
    RiskAssessmentRequest,
    RiskProfileResponse,
)
from app.services.risk_engine import (
    calculate_risk_score,
    get_risk_profile,
    get_questions,
)
from app.routers._deps import get_current_user

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me", response_model=UserResponse, summary="Get current user profile")
async def get_profile(current_user: User = Depends(get_current_user)):
    """Return the authenticated user's profile."""
    return current_user


@router.patch("/me", response_model=UserResponse, summary="Update user profile")
async def update_profile(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the authenticated user's profile fields."""
    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(current_user, field, value)

    db.add(current_user)
    await db.flush()
    await db.refresh(current_user)
    return current_user


@router.post(
    "/me/onboarding",
    response_model=UserResponse,
    summary="Complete onboarding",
)
async def complete_onboarding(
    data: OnboardingRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Submit onboarding data (age, income, goals) and mark onboarding as complete."""
    current_user.age_group = data.age_group
    current_user.income_bracket = data.income_bracket
    current_user.goals = data.goals
    current_user.onboarding_completed = True

    db.add(current_user)
    await db.flush()
    await db.refresh(current_user)
    return current_user


@router.post(
    "/me/profile-picture",
    response_model=UserResponse,
    summary="Upload profile picture",
)
async def upload_profile_picture(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Accepts a JPG/PNG profile photo and stores it in /uploads/profile_pictures/{user_id}.jpg."""
    allowed = {"image/jpeg", "image/png", "image/jpg"}
    if file.content_type not in allowed:
        raise HTTPException(status_code=400, detail="Only JPG and PNG images are accepted")

    upload_dir = "uploads/profile_pictures"
    os.makedirs(upload_dir, exist_ok=True)
    file_path = f"{upload_dir}/{current_user.id}.jpg"

    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    current_user.profile_image_url = file_path
    db.add(current_user)
    await db.flush()
    await db.refresh(current_user)
    return current_user


@router.get(
    "/risk-questions",
    summary="Get risk assessment questions",
)
async def risk_questions(current_user: User = Depends(get_current_user)):
    """Return the 10 behavioral risk assessment questions."""
    return {"questions": get_questions()}


@router.post(
    "/me/risk-assessment",
    response_model=RiskProfileResponse,
    summary="Submit risk assessment",
)
async def submit_risk_assessment(
    data: RiskAssessmentRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Process 10 behavioral answers and calculate the user's risk profile.
    Updates the user record with the calculated profile.
    """
    try:
        score = calculate_risk_score(data.answers)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )

    profile = get_risk_profile(score)

    # Store profile on user
    current_user.risk_profile = {
        "score": profile["score"],
        "level": profile["level"],
        "answers": data.answers,
    }
    db.add(current_user)
    await db.flush()

    return RiskProfileResponse(
        score=profile["score"],
        level=profile["level"],
        description=profile["description"],
        recommended_allocation=profile["recommended_allocation"],
    )
