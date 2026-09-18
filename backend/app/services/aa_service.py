"""
Account Aggregator (AA) Mock Service.
Simulates a read-only, non-transactional consent pipeline for financial data aggregation.
All data flows are mock-architected with explicit privacy control logging.
"""

import uuid
import logging
from datetime import datetime, timedelta, timezone
from pydantic import BaseModel, Field

logger = logging.getLogger("aa_service")


class ConsentRequest(BaseModel):
    """AA consent request payload."""
    user_id: str
    fip_id: str = Field(description="Financial Information Provider ID")
    account_types: list[str] = Field(
        examples=[["SAVINGS", "FIXED_DEPOSIT", "MUTUAL_FUND"]]
    )
    purpose: str = Field(
        default="financial_planning",
        description="Purpose code for data access",
    )
    data_range_from: str = Field(examples=["2025-01-01"])
    data_range_to: str = Field(examples=["2026-06-28"])


class ConsentResponse(BaseModel):
    """AA consent response."""
    consent_id: str
    status: str  # "PENDING", "APPROVED", "REJECTED", "EXPIRED"
    created_at: str
    expires_at: str
    privacy_controls: dict


class AADataResponse(BaseModel):
    """Mock AA data fetch response."""
    consent_id: str
    data_available: bool
    accounts: list[dict]
    privacy_log: dict


# In-memory consent store (mock — would be database in production)
_consent_store: dict[str, dict] = {}


def create_consent(request: ConsentRequest) -> ConsentResponse:
    """
    Create a new AA consent request.
    Logs all privacy control configurations.
    NO transactional execution pathways — read-only consent.
    """
    consent_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    expiry = now + timedelta(hours=24)

    privacy_controls = {
        "consent_mode": "VIEW_ONLY",
        "transaction_execution_allowed": False,  # CRITICAL: Never allow transactions
        "data_encryption": "AES-256-GCM",
        "data_retention_days": 90,
        "purpose_limitation": request.purpose,
        "access_frequency": "ONE_TIME",
        "data_fields_requested": [
            "account_summary",
            "balance",
            "transaction_history",
        ],
        "data_fields_excluded": [
            "account_credentials",
            "authentication_tokens",
            "payment_initiation",
        ],
    }

    # Log privacy configuration
    logger.info(
        "AA Consent Created | consent_id=%s | user_id=%s | fip=%s | "
        "mode=%s | txn_allowed=%s | purpose=%s | expiry=%s",
        consent_id,
        request.user_id,
        request.fip_id,
        privacy_controls["consent_mode"],
        privacy_controls["transaction_execution_allowed"],
        request.purpose,
        expiry.isoformat(),
    )

    consent_data = {
        "consent_id": consent_id,
        "user_id": request.user_id,
        "fip_id": request.fip_id,
        "account_types": request.account_types,
        "status": "APPROVED",  # Mock: auto-approve
        "created_at": now.isoformat(),
        "expires_at": expiry.isoformat(),
        "privacy_controls": privacy_controls,
    }
    _consent_store[consent_id] = consent_data

    return ConsentResponse(**consent_data)


def fetch_account_data(consent_id: str) -> AADataResponse:
    """
    Fetch financial data using an approved consent.
    Returns mock account data with privacy audit log.
    """
    consent = _consent_store.get(consent_id)

    if consent is None:
        return AADataResponse(
            consent_id=consent_id,
            data_available=False,
            accounts=[],
            privacy_log={"error": "Consent not found or expired"},
        )

    # Verify consent is still valid
    expiry = datetime.fromisoformat(consent["expires_at"])
    if datetime.now(timezone.utc) > expiry:
        logger.warning("AA data fetch attempted with expired consent: %s", consent_id)
        return AADataResponse(
            consent_id=consent_id,
            data_available=False,
            accounts=[],
            privacy_log={"error": "Consent expired", "expired_at": consent["expires_at"]},
        )

    # Mock account data (read-only, no transaction capability)
    mock_accounts = [
        {
            "account_type": "SAVINGS",
            "fip_id": consent["fip_id"],
            "masked_account_number": "XXXX-XXXX-1234",
            "balance": 285000.00,
            "currency": "INR",
            "recent_transactions_count": 45,
            "holder_name": "MASKED",
        },
        {
            "account_type": "FIXED_DEPOSIT",
            "fip_id": consent["fip_id"],
            "masked_account_number": "XXXX-XXXX-5678",
            "principal": 500000.00,
            "interest_rate": 7.1,
            "maturity_date": "2027-01-15",
            "currency": "INR",
        },
    ]

    # Privacy audit log
    privacy_log = {
        "consent_id": consent_id,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "data_scope": "READ_ONLY",
        "transaction_execution_blocked": True,
        "fields_returned": ["balance", "account_summary"],
        "fields_withheld": ["credentials", "payment_initiation"],
        "encryption_applied": True,
        "audit_trail_id": str(uuid.uuid4()),
    }

    logger.info(
        "AA Data Fetched | consent_id=%s | accounts=%d | audit=%s",
        consent_id,
        len(mock_accounts),
        privacy_log["audit_trail_id"],
    )

    return AADataResponse(
        consent_id=consent_id,
        data_available=True,
        accounts=mock_accounts,
        privacy_log=privacy_log,
    )


def revoke_consent(consent_id: str) -> bool:
    """Revoke an active consent and purge cached data."""
    if consent_id in _consent_store:
        logger.info("AA Consent Revoked | consent_id=%s", consent_id)
        del _consent_store[consent_id]
        return True
    return False
