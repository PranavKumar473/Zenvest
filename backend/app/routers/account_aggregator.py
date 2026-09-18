"""
Account Aggregator API routes.
Mock-architected consent pipeline for read-only financial data ingestion.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from app.models.user import User
from app.services.aa_service import (
    ConsentRequest,
    ConsentResponse,
    AADataResponse,
    create_consent,
    fetch_account_data,
    revoke_consent,
)
from app.routers._deps import get_current_user

router = APIRouter(prefix="/account-aggregator", tags=["Account Aggregator"])


@router.post(
    "/consent",
    response_model=ConsentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create AA consent",
)
async def create_aa_consent(
    request: ConsentRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Create a read-only consent request for Account Aggregator data.
    No transactional execution pathways are permitted.
    """
    request.user_id = current_user.id
    return create_consent(request)


@router.get(
    "/data/{consent_id}",
    response_model=AADataResponse,
    summary="Fetch AA data",
)
async def fetch_aa_data(
    consent_id: str,
    current_user: User = Depends(get_current_user),
):
    """
    Fetch financial data using an approved consent.
    Returns mock account data with full privacy audit log.
    """
    data = fetch_account_data(consent_id)

    if not data.data_available:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No data available for this consent",
        )

    return data


@router.delete(
    "/consent/{consent_id}",
    summary="Revoke AA consent",
)
async def revoke_aa_consent(
    consent_id: str,
    current_user: User = Depends(get_current_user),
):
    """Revoke an active consent and purge all cached data."""
    success = revoke_consent(consent_id)

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Consent not found",
        )

    return {"message": "Consent revoked successfully", "consent_id": consent_id}
