"""
Billing service — recurring monthly consultation-fee subscriptions.

Uses Razorpay Subscriptions (UPI Autopay / e-mandate capable), which the
Flutter app checks out via the `razorpay_flutter` SDK using the
`subscription_id` this service returns. Razorpay then charges the investor
every billing cycle server-side; we only need to react to webhook events
to keep Subscription.status in sync.

Falls back to MockBillingProvider whenever Razorpay credentials are not
configured, so local development never requires a live merchant account.
"""

import hmac
import hashlib
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from app.config import get_settings

settings = get_settings()


@dataclass
class SubscriptionCheckoutResult:
    provider: str  # "mock" | "razorpay"
    provider_plan_id: str
    provider_subscription_id: str
    checkout_key: Optional[str] = None  # Razorpay key_id the client SDK needs


class BillingProvider(ABC):
    @abstractmethod
    async def create_subscription(
        self,
        advisor_id: str,
        investor_id: str,
        amount_monthly: float,
    ) -> SubscriptionCheckoutResult:
        ...

    @abstractmethod
    def verify_payment_signature(
        self, subscription_id: str, payment_id: str, signature: str
    ) -> bool:
        ...

    @abstractmethod
    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        ...


class MockBillingProvider(BillingProvider):
    async def create_subscription(
        self,
        advisor_id: str,
        investor_id: str,
        amount_monthly: float,
    ) -> SubscriptionCheckoutResult:
        return SubscriptionCheckoutResult(
            provider="mock",
            provider_plan_id=f"mock_plan_{uuid.uuid4().hex[:10]}",
            provider_subscription_id=f"mock_sub_{uuid.uuid4().hex[:10]}",
            checkout_key=None,
        )

    def verify_payment_signature(
        self, subscription_id: str, payment_id: str, signature: str
    ) -> bool:
        # Mock mode: accept any non-empty signature so the demo flow completes.
        return bool(signature)

    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        return True


class RazorpayBillingProvider(BillingProvider):
    def _client(self):
        import razorpay  # lazy import — optional dependency

        return razorpay.Client(auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET))

    async def create_subscription(
        self,
        advisor_id: str,
        investor_id: str,
        amount_monthly: float,
    ) -> SubscriptionCheckoutResult:
        client = self._client()
        amount_paise = int(round(amount_monthly * 100))

        plan = client.plan.create({
            "period": "monthly",
            "interval": 1,
            "item": {
                "name": f"Advisory consultation — {advisor_id}",
                "amount": amount_paise,
                "currency": "INR",
            },
            "notes": {"advisor_id": advisor_id},
        })

        subscription = client.subscription.create({
            "plan_id": plan["id"],
            "customer_notify": 1,
            "total_count": 12,  # 12 monthly cycles; renews via a fresh checkout after
            "notes": {"advisor_id": advisor_id, "investor_id": investor_id},
        })

        return SubscriptionCheckoutResult(
            provider="razorpay",
            provider_plan_id=plan["id"],
            provider_subscription_id=subscription["id"],
            checkout_key=settings.RAZORPAY_KEY_ID,
        )

    def verify_payment_signature(
        self, subscription_id: str, payment_id: str, signature: str
    ) -> bool:
        expected = hmac.new(
            settings.RAZORPAY_KEY_SECRET.encode(),
            f"{payment_id}|{subscription_id}".encode(),
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    def verify_webhook_signature(self, payload: bytes, signature: str) -> bool:
        expected = hmac.new(
            settings.RAZORPAY_WEBHOOK_SECRET.encode(), payload, hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature)


def get_billing_provider() -> BillingProvider:
    if settings.RAZORPAY_KEY_ID and settings.RAZORPAY_KEY_SECRET:
        return RazorpayBillingProvider()
    return MockBillingProvider()
