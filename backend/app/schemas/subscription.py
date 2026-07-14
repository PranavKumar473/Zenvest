"""
Subscription request/response schemas.
Recurring monthly consultation-fee checkout between investor and advisor.
"""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class CreateSubscriptionPayload(BaseModel):
    advisor_id: str


class SubscriptionCheckoutResponse(BaseModel):
    """
    Returned to the Flutter app so it can open razorpay_flutter's native
    checkout using `provider_subscription_id`.
    """
    subscription_id: str
    provider: str
    provider_subscription_id: str
    checkout_key: Optional[str] = None
    amount_monthly: float
    advisor_name: str


class VerifySubscriptionPaymentPayload(BaseModel):
    subscription_id: str = Field(..., description="Our internal Subscription.id")
    razorpay_payment_id: str
    razorpay_subscription_id: str
    razorpay_signature: str


class SubscriptionResponse(BaseModel):
    id: str
    investor_id: str
    advisor_id: str
    counterparty_name: Optional[str] = None
    # The advisor's name when the investor lists their own subscriptions,
    # or the investor's name when an advisor lists their client subscriptions.
    amount_monthly: float
    provider: str
    status: str
    current_period_end: Optional[datetime] = None
    created_at: datetime

    model_config = {"from_attributes": True}
