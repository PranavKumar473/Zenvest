"""
GST verification service.
Cross-checks an advisor's declared GSTIN against the GST Portal (GSTN) before
it is shown as verified on their public profile.

Real integration requires an empanelled GSP (GST Suvidha Provider) API key —
until GST_PORTAL_API_URL / GST_PORTAL_API_KEY are configured, verification
runs against MockGstPortalProvider so onboarding keeps working end-to-end
in development.
"""

import re
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from app.config import get_settings

settings = get_settings()

# GSTIN format (15 chars): 2-digit state code, 10-char PAN, 1 entity code,
# literal 'Z', 1 checksum character.
GSTIN_PATTERN = re.compile(
    r"^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$"
)


@dataclass
class GstVerificationResult:
    status: str  # "verified" | "failed"
    legal_name: Optional[str] = None
    reason: Optional[str] = None


class GstVerificationProvider(ABC):
    """Contract every GST verification backend must implement."""

    @abstractmethod
    async def verify(self, gstin: str, declared_name: str) -> GstVerificationResult:
        ...


class MockGstPortalProvider(GstVerificationProvider):
    """
    Deterministic mock of the GST Portal search API
    (https://services.gst.gov.in/services/searchtp).
    Accepts any well-formed GSTIN and echoes the declared name back as
    "verified" — this is a placeholder for the real GSP integration.
    """

    async def verify(self, gstin: str, declared_name: str) -> GstVerificationResult:
        if not GSTIN_PATTERN.match(gstin):
            return GstVerificationResult(
                status="failed",
                reason="GSTIN does not match the 15-character GST Portal format",
            )
        return GstVerificationResult(status="verified", legal_name=declared_name)


class GstPortalApiProvider(GstVerificationProvider):
    """
    Real GSP-backed provider. Wired up once GST_PORTAL_API_URL and
    GST_PORTAL_API_KEY are configured. Left unimplemented here since the
    request/response contract is specific to the chosen GSP vendor
    (e.g. Cygnet, ClearTax, Karza) — swap this in without touching callers.
    """

    async def verify(self, gstin: str, declared_name: str) -> GstVerificationResult:
        raise NotImplementedError(
            "Configure a GSP vendor SDK/HTTP client here using "
            "settings.GST_PORTAL_API_URL and settings.GST_PORTAL_API_KEY."
        )


def get_gst_provider() -> GstVerificationProvider:
    if settings.GST_PORTAL_API_URL and settings.GST_PORTAL_API_KEY:
        return GstPortalApiProvider()
    return MockGstPortalProvider()


async def verify_advisor_gst(gstin: str, declared_name: str) -> GstVerificationResult:
    """Entry point used by routers — resolves the active provider and verifies."""
    provider = get_gst_provider()
    return await provider.verify(gstin.strip().upper(), declared_name)
