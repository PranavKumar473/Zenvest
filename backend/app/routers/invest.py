"""
Universal "Invest" workflow — applies to every asset type and entry point
(fund directory, top-5 recommendations, scheme detail view). Executes
through app/services/investment_service.py, which silently registers the
transaction under the platform's corporate ARN and, when a human advisor
guided the investor, records EUIN-based attribution for internal
commission-split accounting. See app/schemas/investment.py for the request
shape driving the "Who guided your investment?" modal.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.routers._deps import get_current_user
from app.schemas.investment import InvestRequest, InvestResponse
from app.services.investment_service import record_investment

router = APIRouter(prefix="/invest", tags=["Invest"])


@router.post("", response_model=InvestResponse, summary="Execute an investment")
async def invest(
    data: InvestRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await record_investment(
        db,
        investor=current_user,
        asset_type=data.asset_type,
        scheme_name=data.scheme_name,
        suggested_amount=data.suggested_amount,
        actual_amount=data.actual_amount,
        confirmed=True,
        investment_mode=data.investment_mode,
        advisor_source=data.guidance.source,
        advisor_id=data.guidance.advisor_id,
        advisor_name=data.guidance.advisor_name,
        advisor_euin=data.guidance.advisor_euin,
    )
    return InvestResponse(**result)
