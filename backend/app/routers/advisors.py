"""
Advisor listing and profile API routes.
Serves verified advisor profiles to investors with masked sensitive data.
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from app.database import get_db
from app.models.user import User
from app.routers._deps import get_current_user
from app.schemas.user import AdvisorPublicResponse
from app.services import gst_service, telephony_service

router = APIRouter(prefix="/advisors", tags=["Human Advisors"])


# --- Helper: mask PAN number ---
def _mask_pan(pan: Optional[str]) -> Optional[str]:
    if not pan or len(pan) < 5:
        return pan
    return pan[:5] + "****" + pan[-1]


# --- Helper: mask phone number ---
def _mask_phone(phone: Optional[str]) -> Optional[str]:
    if not phone or len(phone) < 6:
        return phone
    return phone[:3] + "****" + phone[-3:]


# --- Helper: format consultation fee ---
def _format_charges(fee: Optional[float]) -> Optional[str]:
    if fee is None:
        return "Contact for pricing"
    return f"₹{fee:,.0f} / month"


def _user_to_advisor_response(user: User) -> AdvisorPublicResponse:
    """Convert a User ORM object to the public advisor response."""
    return AdvisorPublicResponse(
        id=user.id,
        name=user.advisor_name or user.name,
        email=user.email,
        phone_number=_mask_phone(user.phone_number),
        profile_image_url=user.profile_image_url,
        address=user.address,
        pan_masked=_mask_pan(user.pan_number),
        arn_number=user.arn_number or "ARN-00000",
        arn_verified=user.arn_verified,
        sebi_registration_number=user.sebi_registration_number,
        ina_number=user.sebi_registration_number,
        gst_number=user.gst_number,
        gst_verified=user.gst_verified,
        gst_verification_status=user.gst_verification_status,
        consultation_fee_monthly=float(user.consultation_fee_monthly) if user.consultation_fee_monthly else None,
        bio=user.bio,
        specializations=user.specializations,
        experience_years=user.experience_years,
        rating=5.0,  # TODO: compute from actual ratings
        charges=_format_charges(float(user.consultation_fee_monthly) if user.consultation_fee_monthly else None),
    )


# --- Pre-defined fallback mock advisors (for demo until real advisors register) ---
FALLBACK_ADVISORS = [
    AdvisorPublicResponse(
        id="mock-advisor-id-0",
        name="Aarav Mehta",
        email="aarav@financialclarity.app",
        phone_number="+91 98***43210",
        arn_number="ARN-123456",
        arn_verified=True,
        gst_number="27AABCU9603R1ZM",
        gst_verified=True,
        pan_masked="ABCPD****E",
        address={"city": "Mumbai", "state": "Maharashtra", "pincode": "400001"},
        consultation_fee_monthly=1500.0,
        bio="Certified Financial Planner (CFP) with a passion for helping young professionals build long-term wealth. Specialized in mutual fund selection, asset allocation, and tax harvesting.",
        specializations=["Mutual Funds", "Wealth Growth", "Tax Planning"],
        experience_years=8,
        rating=4.8,
        charges="₹1,500 / month",
    ),
    AdvisorPublicResponse(
        id="mock-advisor-id-1",
        name="Priya Sharma",
        email="priya@financialclarity.app",
        phone_number="+91 87***65432",
        arn_number="ARN-654321",
        arn_verified=True,
        gst_number=None,
        gst_verified=False,
        pan_masked="BCDPF****G",
        address={"city": "Delhi", "state": "Delhi", "pincode": "110001"},
        consultation_fee_monthly=2500.0,
        bio="Retired senior fund manager from a top AMFI house. Helping families navigate retirement planning, debt instruments, and stable dividend portfolios.",
        specializations=["Bonds & Fixed Income", "Retirement Planning", "Estate Planning"],
        experience_years=22,
        rating=4.9,
        charges="₹2,500 / month",
    ),
    AdvisorPublicResponse(
        id="mock-advisor-id-2",
        name="Rohan Das",
        email="rohan@financialclarity.app",
        phone_number="+91 76***21098",
        arn_number="ARN-987654",
        arn_verified=True,
        gst_number="19AABCU9603R1ZR",
        gst_verified=True,
        pan_masked="CDEFG****H",
        address={"city": "Kolkata", "state": "West Bengal", "pincode": "700001"},
        consultation_fee_monthly=1800.0,
        bio="Aggressive growth strategist focused on equity markets, international indexing, and multi-asset dynamic rebalancing. Helping clients maximize returns with measured risk.",
        specializations=["Stocks & Equities", "Goal-Based Planning", "Gold & Alternatives"],
        experience_years=12,
        rating=4.7,
        charges="₹1,800 / month",
    ),
]


@router.get(
    "",
    response_model=list[AdvisorPublicResponse],
    summary="Get all verified AMFI-registered advisors",
)
async def list_advisors(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch all users registered as verified advisors."""
    result = await db.execute(
        select(User).where(
            User.user_type == "advisor",
            User.arn_verified == True,
        )
    )
    db_advisors = result.scalars().all()

    if not db_advisors:
        # Return fallback mock advisors for demo
        return FALLBACK_ADVISORS

    return [_user_to_advisor_response(user) for user in db_advisors]


@router.get(
    "/all",
    response_model=list[AdvisorPublicResponse],
    summary="Get all advisors including unverified (for admin/debug)",
)
async def list_all_advisors(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch all advisor-type users regardless of verification status."""
    result = await db.execute(
        select(User).where(User.user_type == "advisor")
    )
    db_advisors = result.scalars().all()

    if not db_advisors:
        return FALLBACK_ADVISORS

    return [_user_to_advisor_response(user) for user in db_advisors]


@router.get(
    "/{advisor_id}",
    response_model=AdvisorPublicResponse,
    summary="Get advisor details by ID",
)
async def get_advisor(
    advisor_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fetch details for a specific advisor."""
    # Check fallback mock IDs
    if advisor_id.startswith("mock-advisor-id-"):
        idx = int(advisor_id.split("-")[-1])
        if 0 <= idx < len(FALLBACK_ADVISORS):
            return FALLBACK_ADVISORS[idx]
        raise HTTPException(status_code=404, detail="Advisor not found")

    result = await db.execute(
        select(User).where(User.id == advisor_id, User.user_type == "advisor")
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Advisor not found",
        )

    return _user_to_advisor_response(user)


class DemoCallResponse(BaseModel):
    session_id: str
    masked_number: str
    expires_in: int  # in seconds


@router.post(
    "/{advisor_id}/demo-call",
    response_model=DemoCallResponse,
    summary="Initiate a secure demo call session",
)
async def initiate_demo_call(
    advisor_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a virtual calling session with a masked phone number."""
    valid_advisor = False
    if advisor_id.startswith("mock-advisor-id-"):
        idx = int(advisor_id.split("-")[-1])
        if 0 <= idx < len(FALLBACK_ADVISORS):
            valid_advisor = True
    else:
        result = await db.execute(
            select(User).where(User.id == advisor_id, User.user_type == "advisor")
        )
        if result.scalar_one_or_none():
            valid_advisor = True

    if not valid_advisor:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Advisor not found",
        )

    session_id = f"sec_sess_{uuid.uuid4().hex[:12]}"
    masked = await telephony_service.start_masked_call(
        session_id=session_id,
        investor_phone=current_user.phone_number,
        advisor_phone=None,  # demo calls don't bridge to a real advisor line
    )

    return DemoCallResponse(
        session_id=session_id,
        masked_number=masked.masked_number,
        expires_in=masked.expires_in,
    )


@router.post(
    "/me/complete-onboarding",
    response_model=AdvisorPublicResponse,
    summary="Advisor finishes the post-registration verification profile",
)
async def complete_advisor_onboarding(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Marks onboarding_completed once the minimum verification fields (PAN,
    address) are on file. Called after the advisor onboarding screen's PATCH
    /users/me and optional GST verification / profile picture upload steps.
    """
    if current_user.user_type != "advisor":
        raise HTTPException(status_code=403, detail="Only advisors can complete advisor onboarding")

    if not current_user.pan_number:
        raise HTTPException(status_code=400, detail="PAN number is required to complete verification")
    if not current_user.address:
        raise HTTPException(status_code=400, detail="Address is required to complete verification")

    current_user.onboarding_completed = True
    db.add(current_user)
    await db.flush()
    await db.refresh(current_user)

    return _user_to_advisor_response(current_user)


class GstVerifyResponse(BaseModel):
    gst_verification_status: str
    gst_verified: bool
    gst_legal_name: Optional[str] = None
    reason: Optional[str] = None


@router.post(
    "/me/verify-gst",
    response_model=GstVerifyResponse,
    summary="Advisor triggers GST Portal verification of their declared GSTIN",
)
async def verify_my_gst(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Cross-checks current_user.gst_number against the GST Portal (mock provider
    in local dev). Updates gst_verification_status / gst_verified / gst_legal_name.
    """
    if current_user.user_type != "advisor":
        raise HTTPException(status_code=403, detail="Only advisors can verify GST")

    if not current_user.gst_number:
        raise HTTPException(status_code=400, detail="No GST number on file to verify")

    current_user.gst_verification_status = "pending"
    db.add(current_user)
    await db.flush()

    result = await gst_service.verify_advisor_gst(
        current_user.gst_number,
        current_user.advisor_name or current_user.name,
    )

    current_user.gst_verification_status = result.status
    current_user.gst_verified = result.status == "verified"
    current_user.gst_legal_name = result.legal_name
    db.add(current_user)
    await db.flush()

    return GstVerifyResponse(
        gst_verification_status=current_user.gst_verification_status,
        gst_verified=current_user.gst_verified,
        gst_legal_name=current_user.gst_legal_name,
        reason=result.reason,
    )
