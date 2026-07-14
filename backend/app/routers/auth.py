"""
Authentication API routes.
Handles registration, login, token refresh, and biometric authentication.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.schemas.auth import (
    RegisterRequest,
    LoginRequest,
    TokenResponse,
    RefreshRequest,
    BiometricChallengeResponse,
    BiometricVerifyRequest,
)
from app.services.auth_service import (
    hash_password,
    authenticate_user,
    create_token_pair,
    refresh_tokens,
    generate_biometric_challenge,
)
from app.routers._deps import get_current_user

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user",
)
async def register(
    request: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """Create a new user account and return JWT tokens."""
    from sqlalchemy import select

    # Check if email already exists
    existing = await db.execute(
        select(User).where(User.email == request.email)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    # Create user
    user = User(
        name=request.name,
        email=request.email,
        hashed_password=hash_password(request.password),
        user_type=request.user_type,
        arn_number=request.arn_number,
        advisor_name=request.advisor_name,
        arn_verified=False,  # always starts unverified
        onboarding_completed=False,  # advisors complete a verification profile step too (see /advisors/me/complete-onboarding)
        gst_number=request.gst_number,
        gst_verified=(request.gst_number is not None and len(request.gst_number) > 0),  # Auto-verify mock GST for MVP
        pan_number=request.pan_number,
        address=request.address,
        sebi_registration_number=request.sebi_registration_number,
        bio=request.bio,
        specializations=request.specializations,
        experience_years=request.experience_years,
        consultation_fee_monthly=request.consultation_fee_monthly,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    # Generate token pair
    tokens = await create_token_pair(db, user)
    return tokens


import os, shutil
from fastapi import UploadFile, File

@router.post(
    "/advisor/upload-license",
    summary="Upload ARN card image for verification",
)
async def upload_arn_license(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Accepts JPG/PNG upload of the physical ARN card.
    Stores it in /uploads/arn_cards/{user_id}.jpg
    For MVP: manual admin review. Production: automated OCR + AMFI API check.
    """
    if current_user.user_type != "advisor":
        raise HTTPException(403, "Only advisor accounts can upload ARN cards")

    allowed = {"image/jpeg", "image/png", "image/jpg"}
    if file.content_type not in allowed:
        raise HTTPException(400, "Only JPG and PNG images are accepted")

    upload_dir = "uploads/arn_cards"
    os.makedirs(upload_dir, exist_ok=True)
    file_path = f"{upload_dir}/{current_user.id}.jpg"

    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    current_user.advisor_license_image_url = file_path
    db.add(current_user)
    await db.commit()

    return {
        "message": "ARN card uploaded successfully. Verification pending review.",
        "file_path": file_path,
        "arn_verified": False,
    }


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Authenticate and get JWT tokens",
)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Authenticate user by email/password and return JWT token pair."""
    user = await authenticate_user(db, request.email, request.password)

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    tokens = await create_token_pair(db, user)
    return tokens


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Refresh access token",
)
async def refresh(
    request: RefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    """Exchange a valid refresh token for a new token pair (rotation)."""
    tokens = await refresh_tokens(db, request.refresh_token)

    if tokens is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    return tokens


@router.post(
    "/biometric/challenge",
    response_model=BiometricChallengeResponse,
    summary="Request biometric authentication challenge",
)
async def biometric_challenge(
    current_user: User = Depends(get_current_user),
):
    """Generate a challenge for biometric authentication."""
    if not current_user.biometric_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Biometric authentication is not enabled for this account",
        )

    challenge_data = generate_biometric_challenge()
    return BiometricChallengeResponse(**challenge_data)


@router.post(
    "/biometric/verify",
    response_model=TokenResponse,
    summary="Verify biometric signature",
)
async def biometric_verify(
    request: BiometricVerifyRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Verify a biometric challenge signature and issue tokens.
    In production, this validates the signature against the stored public key.
    """
    from sqlalchemy import select

    user_result = await db.execute(
        select(User).where(User.id == request.user_id)
    )
    user = user_result.scalar_one_or_none()

    if user is None or not user.biometric_enabled:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Biometric verification failed",
        )

    # In production: verify signature against user.biometric_public_key
    # For now, we accept any valid challenge format (mock)
    if not request.signature or not request.challenge:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid challenge or signature",
        )

    tokens = await create_token_pair(db, user)
    return tokens
