"""
Subscription API routes.
Lets an investor set up a recurring monthly consultation-fee engagement
with an advisor via Razorpay Subscriptions (mock provider in local dev).
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.models.subscription import Subscription
from app.routers._deps import get_current_user
from app.schemas.subscription import (
    CreateSubscriptionPayload,
    SubscriptionCheckoutResponse,
    VerifySubscriptionPaymentPayload,
    SubscriptionResponse,
)
from app.services.billing_service import get_billing_provider

router = APIRouter(prefix="/subscriptions", tags=["Subscriptions"])


@router.post(
    "/checkout",
    response_model=SubscriptionCheckoutResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Investor starts a monthly consultation-fee subscription checkout",
)
async def create_subscription_checkout(
    payload: CreateSubscriptionPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Creates a Subscription row in 'created' status and a matching Razorpay
    plan+subscription. The Flutter app opens razorpay_flutter's checkout with
    the returned provider_subscription_id; the webhook (or verify-payment
    below) flips status to 'active'.
    """
    if current_user.user_type != "user":
        raise HTTPException(status_code=403, detail="Only investors can subscribe to an advisor")

    result = await db.execute(
        select(User).where(User.id == payload.advisor_id, User.user_type == "advisor")
    )
    advisor = result.scalar_one_or_none()
    if not advisor:
        raise HTTPException(status_code=404, detail="Advisor not found")

    if not advisor.consultation_fee_monthly or float(advisor.consultation_fee_monthly) <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This advisor has not configured a monthly consultation fee",
        )

    amount = float(advisor.consultation_fee_monthly)
    provider = get_billing_provider()
    checkout = await provider.create_subscription(
        advisor_id=advisor.id,
        investor_id=current_user.id,
        amount_monthly=amount,
    )

    subscription = Subscription(
        investor_id=current_user.id,
        advisor_id=advisor.id,
        amount_monthly=amount,
        provider=checkout.provider,
        provider_plan_id=checkout.provider_plan_id,
        provider_subscription_id=checkout.provider_subscription_id,
        status="created",
    )
    db.add(subscription)
    await db.flush()
    await db.refresh(subscription)

    return SubscriptionCheckoutResponse(
        subscription_id=subscription.id,
        provider=checkout.provider,
        provider_subscription_id=checkout.provider_subscription_id,
        checkout_key=checkout.checkout_key,
        amount_monthly=amount,
        advisor_name=advisor.advisor_name or advisor.name,
    )


@router.post(
    "/verify-payment",
    response_model=SubscriptionResponse,
    summary="Confirm a Razorpay checkout success client-side (in addition to the webhook)",
)
async def verify_subscription_payment(
    payload: VerifySubscriptionPaymentPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    razorpay_flutter's success callback hands the app a payment_id + signature.
    We verify it here for an immediate UI update; the webhook remains the
    source of truth for subsequent renewal cycles.
    """
    result = await db.execute(
        select(Subscription).where(
            Subscription.id == payload.subscription_id,
            Subscription.investor_id == current_user.id,
        )
    )
    subscription = result.scalar_one_or_none()
    if not subscription:
        raise HTTPException(status_code=404, detail="Subscription not found")

    provider = get_billing_provider()
    is_valid = provider.verify_payment_signature(
        subscription_id=payload.razorpay_subscription_id,
        payment_id=payload.razorpay_payment_id,
        signature=payload.razorpay_signature,
    )
    if not is_valid:
        raise HTTPException(status_code=400, detail="Payment signature verification failed")

    subscription.status = "active"
    db.add(subscription)
    await db.flush()
    await db.refresh(subscription)

    return SubscriptionResponse(
        id=subscription.id,
        investor_id=subscription.investor_id,
        advisor_id=subscription.advisor_id,
        amount_monthly=float(subscription.amount_monthly),
        provider=subscription.provider,
        status=subscription.status,
        current_period_end=subscription.current_period_end,
        created_at=subscription.created_at,
    )


@router.get(
    "/mine",
    response_model=list[SubscriptionResponse],
    summary="Investor lists their subscriptions",
)
async def list_my_subscriptions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Subscription)
        .where(Subscription.investor_id == current_user.id)
        .order_by(Subscription.created_at.desc())
    )
    subs = result.scalars().all()

    responses = []
    for s in subs:
        adv_result = await db.execute(select(User).where(User.id == s.advisor_id))
        advisor = adv_result.scalar_one_or_none()
        responses.append(SubscriptionResponse(
            id=s.id,
            investor_id=s.investor_id,
            advisor_id=s.advisor_id,
            counterparty_name=(advisor.advisor_name or advisor.name) if advisor else "Unknown",
            amount_monthly=float(s.amount_monthly),
            provider=s.provider,
            status=s.status,
            current_period_end=s.current_period_end,
            created_at=s.created_at,
        ))
    return responses


@router.get(
    "/my-clients",
    response_model=list[SubscriptionResponse],
    summary="Advisor lists investors subscribed to their consultation fee",
)
async def list_my_client_subscriptions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.user_type != "advisor":
        raise HTTPException(status_code=403, detail="Only advisors can view client subscriptions")

    result = await db.execute(
        select(Subscription)
        .where(Subscription.advisor_id == current_user.id, Subscription.status == "active")
        .order_by(Subscription.created_at.desc())
    )
    subs = result.scalars().all()

    responses = []
    for s in subs:
        inv_result = await db.execute(select(User).where(User.id == s.investor_id))
        investor = inv_result.scalar_one_or_none()
        responses.append(SubscriptionResponse(
            id=s.id,
            investor_id=s.investor_id,
            advisor_id=s.advisor_id,
            counterparty_name=investor.name if investor else "Unknown",
            amount_monthly=float(s.amount_monthly),
            provider=s.provider,
            status=s.status,
            current_period_end=s.current_period_end,
            created_at=s.created_at,
        ))
    return responses
