"""
Audit logging service.
Records security-relevant events for compliance tracking and anomaly detection.
"""

from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.audit_log import AuditLog


async def log_event(
    db: AsyncSession,
    event_type: str,
    user_id: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
    details: Optional[dict] = None,
) -> AuditLog:
    """
    Create an audit log entry.

    Event types:
    - transaction_sync: Real-time notification sync
    - bulk_import: SMS bulk import
    - sync_decrypt_failure: Failed payload decryption (potential tampering)
    - login_success / login_failure
    - token_refresh
    - notification_access_granted / notification_access_revoked
    - rate_limit_exceeded
    """
    entry = AuditLog(
        user_id=user_id,
        event_type=event_type,
        ip_address=ip_address,
        user_agent=user_agent,
        details=details,
    )
    db.add(entry)
    await db.flush()
    return entry
