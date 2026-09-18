from typing import Optional
"""
Authentication service.
Handles JWT creation, validation, refresh token rotation, and password hashing.
"""

import secrets
import hashlib
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import get_settings
from app.models.user import User
from app.schemas.auth import TokenResponse

settings = get_settings()

# Password hashing context using bcrypt
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its bcrypt hash."""
    return pwd_context.verify(plain_password, hashed_password)


def _hash_token(token: str) -> str:
    """Create SHA-256 hash of a token for secure storage."""
    return hashlib.sha256(token.encode()).hexdigest()


def create_access_token(user_id: str) -> str:
    """
    Create a short-lived JWT access token.
    Contains user_id as subject, issued-at, and expiry timestamps.
    """
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES),
        "type": "access",
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token() -> str:
    """Create a cryptographically secure refresh token."""
    return secrets.token_urlsafe(64)


def decode_access_token(token: str) -> Optional[dict]:
    """
    Decode and validate a JWT access token.
    Returns the payload dict or None if invalid/expired.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        if payload.get("type") != "access":
            return None
        return payload
    except JWTError:
        return None


async def authenticate_user(
    db: AsyncSession, email: str, password: str
) -> Optional[User]:
    """
    Authenticate user by email and password.
    Returns the User object if credentials are valid, None otherwise.
    """
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user is None:
        # Perform dummy hash to prevent timing attacks
        pwd_context.hash("dummy")
        return None

    if not verify_password(password, user.hashed_password):
        return None

    return user


async def create_token_pair(db: AsyncSession, user: User) -> TokenResponse:
    """
    Create a new access + refresh token pair.
    Stores the hashed refresh token in the database for rotation validation.
    """
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token()

    # Store hashed refresh token
    user.refresh_token_hash = _hash_token(refresh_token)
    db.add(user)
    await db.flush()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


async def refresh_tokens(
    db: AsyncSession, refresh_token: str
) -> Optional[TokenResponse]:
    """
    Validate a refresh token and issue a new token pair.
    Implements refresh token rotation — old token is invalidated.
    Returns None if the refresh token is invalid.
    """
    token_hash = _hash_token(refresh_token)

    result = await db.execute(
        select(User).where(User.refresh_token_hash == token_hash)
    )
    user = result.scalar_one_or_none()

    if user is None:
        return None

    # Issue new token pair (rotating the refresh token)
    return await create_token_pair(db, user)


def generate_biometric_challenge() -> dict:
    """Generate a random challenge for biometric authentication."""
    challenge = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=5)
    return {
        "challenge": challenge,
        "expires_at": expires_at.isoformat(),
    }
