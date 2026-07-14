"""
Telephony service — masked-number call bridging and recording.

Neither party's real mobile number is ever exposed to the other. The
provider places an outbound call to the investor from a shared masked
Twilio number, and on answer bridges it to the advisor's real number —
both sides see only the masked number as caller ID. The whole session is
recorded server-side for compliance; the recording lands via a webhook
(see routers/webhooks.py) and is attached to the CallSession row.

Falls back to MockTelephonyProvider whenever Twilio credentials are not
configured, so local development and CI never require a live account.
"""

import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from app.config import get_settings

settings = get_settings()


@dataclass
class MaskedSessionResult:
    masked_number: str
    provider: str  # "mock" | "twilio"
    provider_call_sid: Optional[str] = None
    expires_in: int = 600


class TelephonyProvider(ABC):
    @abstractmethod
    async def start_masked_session(
        self,
        session_id: str,
        investor_phone: Optional[str],
        advisor_phone: Optional[str],
    ) -> MaskedSessionResult:
        ...

    @abstractmethod
    async def end_session(self, provider_call_sid: Optional[str]) -> None:
        ...


class MockTelephonyProvider(TelephonyProvider):
    """Deterministic masked number, no real call is placed. Used for local dev/demo."""

    async def start_masked_session(
        self,
        session_id: str,
        investor_phone: Optional[str],
        advisor_phone: Optional[str],
    ) -> MaskedSessionResult:
        unique_digits = str(abs(hash(session_id)) % 900 + 100)
        return MaskedSessionResult(
            masked_number=f"+91 14099 XXXXX (ext: {unique_digits})",
            provider="mock",
            provider_call_sid=f"mock_call_{uuid.uuid4().hex[:12]}",
            expires_in=600,
        )

    async def end_session(self, provider_call_sid: Optional[str]) -> None:
        return None


class TwilioTelephonyProvider(TelephonyProvider):
    """
    Bridges investor <-> advisor through settings.TWILIO_MASKING_NUMBER.
    Requires both parties' real phone numbers to be on file (User.phone_number);
    if either is missing, the caller should fall back to in-app chat only.
    """

    def _client(self):
        from twilio.rest import Client  # lazy import — optional dependency

        return Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)

    async def start_masked_session(
        self,
        session_id: str,
        investor_phone: Optional[str],
        advisor_phone: Optional[str],
    ) -> MaskedSessionResult:
        from twilio.twiml.voice_response import Dial, VoiceResponse

        if not investor_phone or not advisor_phone:
            raise ValueError(
                "Both parties must have a verified phone number on file to "
                "start a masked call session"
            )
        if not settings.TWILIO_MASKING_NUMBER:
            raise ValueError("TWILIO_MASKING_NUMBER is not configured")

        response = VoiceResponse()
        dial = Dial(
            caller_id=settings.TWILIO_MASKING_NUMBER,
            record="record-from-answer-dual",
            recording_status_callback=settings.TWILIO_RECORDING_STATUS_CALLBACK_URL or None,
            recording_status_callback_event="completed",
        )
        dial.number(advisor_phone)
        response.append(dial)

        call = self._client().calls.create(
            to=investor_phone,
            from_=settings.TWILIO_MASKING_NUMBER,
            twiml=str(response),
            status_callback=settings.TWILIO_RECORDING_STATUS_CALLBACK_URL or None,
            status_callback_event=["initiated", "ringing", "answered", "completed"],
        )

        return MaskedSessionResult(
            masked_number=settings.TWILIO_MASKING_NUMBER,
            provider="twilio",
            provider_call_sid=call.sid,
            expires_in=600,
        )

    async def end_session(self, provider_call_sid: Optional[str]) -> None:
        if not provider_call_sid:
            return
        self._client().calls(provider_call_sid).update(status="completed")


def get_telephony_provider() -> TelephonyProvider:
    if settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN:
        return TwilioTelephonyProvider()
    return MockTelephonyProvider()


async def start_masked_call(
    session_id: str,
    investor_phone: Optional[str],
    advisor_phone: Optional[str],
) -> MaskedSessionResult:
    provider = get_telephony_provider()
    return await provider.start_masked_session(session_id, investor_phone, advisor_phone)


async def end_masked_call(provider_call_sid: Optional[str]) -> None:
    provider = get_telephony_provider()
    await provider.end_session(provider_call_sid)
