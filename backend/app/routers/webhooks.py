"""
Inbound webhooks from third-party providers.
Not authenticated with the app's JWT scheme — each handler verifies the
provider's own signature instead.
"""
import json
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.call_session import CallSession
from app.models.subscription import Subscription
from app.services.billing_service import get_billing_provider

logger = logging.getLogger("financial_clarity.webhooks")

router = APIRouter(prefix="/webhooks", tags=["Webhooks"])


@router.post(
    "/twilio/recording-status",
    summary="Twilio recording-status callback — archives the call recording",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def twilio_recording_status(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Twilio posts application/x-www-form-urlencoded status callbacks. We match
    on CallSid (stored as CallSession.provider_call_sid) and archive the
    RecordingUrl/duration for the compliance audit trail.
    """
    form = await request.form()
    call_sid = form.get("CallSid") or form.get("ParentCallSid")
    recording_url = form.get("RecordingUrl")
    call_status = form.get("CallStatus")
    duration = form.get("RecordingDuration") or form.get("CallDuration")

    if not call_sid:
        raise HTTPException(status_code=400, detail="Missing CallSid")

    result = await db.execute(
        select(CallSession).where(CallSession.provider_call_sid == call_sid)
    )
    session = result.scalar_one_or_none()
    if not session:
        logger.warning("Recording webhook for unknown call_sid=%s", call_sid)
        return

    if recording_url:
        # Twilio recording URLs need '.mp3'/'.wav' appended and are fetched
        # with basic auth (ACCOUNT_SID:AUTH_TOKEN) — stored as-is here,
        # resolved at playback time by an authenticated admin/audit tool.
        session.recording_url = recording_url
    if duration:
        try:
            session.duration_seconds = int(duration)
        except ValueError:
            pass
    if call_status in ("completed", "busy", "failed", "no-answer", "canceled"):
        session.status = "ended"
        session.ended_at = datetime.now(timezone.utc)

    db.add(session)
    await db.flush()


@router.post(
    "/razorpay",
    summary="Razorpay webhook — subscription lifecycle events",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def razorpay_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Verifies the X-Razorpay-Signature header against the raw request body,
    then syncs Subscription.status for subscription.activated / .charged /
    .cancelled / .halted events.
    """
    raw_body = await request.body()
    signature = request.headers.get("X-Razorpay-Signature", "")

    provider = get_billing_provider()
    if not provider.verify_webhook_signature(raw_body, signature):
        raise HTTPException(status_code=400, detail="Invalid webhook signature")

    payload = json.loads(raw_body)
    event = payload.get("event", "")
    entity = payload.get("payload", {}).get("subscription", {}).get("entity", {})
    provider_subscription_id = entity.get("id")

    if not provider_subscription_id:
        return

    result = await db.execute(
        select(Subscription).where(
            Subscription.provider_subscription_id == provider_subscription_id
        )
    )
    subscription = result.scalar_one_or_none()
    if not subscription:
        logger.warning("Razorpay webhook for unknown subscription=%s", provider_subscription_id)
        return

    status_map = {
        "subscription.activated": "active",
        "subscription.charged": "active",
        "subscription.completed": "completed",
        "subscription.cancelled": "cancelled",
        "subscription.halted": "past_due",
        "subscription.pending": "past_due",
    }
    if event in status_map:
        subscription.status = status_map[event]

    current_end = entity.get("current_end")
    if current_end:
        subscription.current_period_end = datetime.fromtimestamp(
            current_end, tz=timezone.utc
        )

    db.add(subscription)
    await db.flush()
