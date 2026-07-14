"""
Advisor Request API routes.
Handles the investor → advisor request/approval workflow, chat, and call sessions.
"""
from typing import Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
import uuid

from app.database import get_db
from app.models.user import User
from app.models.advisor_request import AdvisorRequest
from app.models.chat_message import ChatMessage
from app.models.call_session import CallSession
from app.routers._deps import get_current_user
from app.services import telephony_service

router = APIRouter(prefix="/advisor-requests", tags=["Advisor Requests"])


# ─── Schemas ────────────────────────────────────────────────────────

class CreateRequestPayload(BaseModel):
    advisor_id: str
    message: Optional[str] = Field(None, max_length=1000)


class RespondRequestPayload(BaseModel):
    status: str = Field(..., pattern="^(accepted|rejected)$")
    response_note: Optional[str] = Field(None, max_length=1000)


class SendMessagePayload(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)


class RequestResponse(BaseModel):
    id: str
    investor_id: str
    advisor_id: str
    status: str
    message: Optional[str] = None
    advisor_response: Optional[str] = None
    investor_name: Optional[str] = None
    advisor_name: Optional[str] = None
    investor_risk_profile: Optional[dict] = None
    created_at: datetime
    responded_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ChatMessageResponse(BaseModel):
    id: str
    request_id: str
    sender_id: str
    receiver_id: str
    content: str
    message_type: str
    is_read: bool
    created_at: datetime
    sender_name: Optional[str] = None

    model_config = {"from_attributes": True}


class CallSessionResponse(BaseModel):
    session_id: str
    masked_number: str
    expires_in: int


# ─── Request Endpoints ──────────────────────────────────────────────

@router.post(
    "",
    response_model=RequestResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Investor sends request to advisor",
)
async def create_request(
    payload: CreateRequestPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Investor requests to connect with an advisor. Must not already have a pending request."""
    if current_user.user_type != "user":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only investors can send advisor requests",
        )

    # Check if advisor exists
    result = await db.execute(
        select(User).where(User.id == payload.advisor_id, User.user_type == "advisor")
    )
    advisor = result.scalar_one_or_none()
    if not advisor:
        raise HTTPException(status_code=404, detail="Advisor not found")

    # Check for existing pending request
    existing = await db.execute(
        select(AdvisorRequest).where(
            AdvisorRequest.investor_id == current_user.id,
            AdvisorRequest.advisor_id == payload.advisor_id,
            AdvisorRequest.status == "pending",
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You already have a pending request with this advisor",
        )

    request = AdvisorRequest(
        investor_id=current_user.id,
        advisor_id=payload.advisor_id,
        status="pending",
        message=payload.message,
        investor_risk_profile=current_user.risk_profile,
    )
    db.add(request)
    await db.flush()
    await db.refresh(request)

    return RequestResponse(
        id=request.id,
        investor_id=request.investor_id,
        advisor_id=request.advisor_id,
        status=request.status,
        message=request.message,
        investor_name=current_user.name,
        advisor_name=advisor.advisor_name or advisor.name,
        investor_risk_profile=request.investor_risk_profile,
        created_at=request.created_at,
        responded_at=request.responded_at,
    )


@router.get(
    "/incoming",
    response_model=list[RequestResponse],
    summary="Advisor views incoming requests",
)
async def get_incoming_requests(
    status_filter: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Advisor sees all investor requests directed at them."""
    if current_user.user_type != "advisor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only advisors can view incoming requests",
        )

    query = select(AdvisorRequest).where(
        AdvisorRequest.advisor_id == current_user.id
    )
    if status_filter:
        query = query.where(AdvisorRequest.status == status_filter)
    query = query.order_by(AdvisorRequest.created_at.desc())

    result = await db.execute(query)
    requests = result.scalars().all()

    responses = []
    for req in requests:
        # Fetch investor name
        inv_result = await db.execute(select(User).where(User.id == req.investor_id))
        investor = inv_result.scalar_one_or_none()

        responses.append(RequestResponse(
            id=req.id,
            investor_id=req.investor_id,
            advisor_id=req.advisor_id,
            status=req.status,
            message=req.message,
            advisor_response=req.advisor_response,
            investor_name=investor.name if investor else "Unknown",
            advisor_name=current_user.advisor_name or current_user.name,
            investor_risk_profile=req.investor_risk_profile,
            created_at=req.created_at,
            responded_at=req.responded_at,
        ))

    return responses


@router.get(
    "/outgoing",
    response_model=list[RequestResponse],
    summary="Investor views their sent requests",
)
async def get_outgoing_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Investor sees all requests they have sent."""
    query = select(AdvisorRequest).where(
        AdvisorRequest.investor_id == current_user.id
    ).order_by(AdvisorRequest.created_at.desc())

    result = await db.execute(query)
    requests = result.scalars().all()

    responses = []
    for req in requests:
        adv_result = await db.execute(select(User).where(User.id == req.advisor_id))
        advisor = adv_result.scalar_one_or_none()

        responses.append(RequestResponse(
            id=req.id,
            investor_id=req.investor_id,
            advisor_id=req.advisor_id,
            status=req.status,
            message=req.message,
            advisor_response=req.advisor_response,
            investor_name=current_user.name,
            advisor_name=(advisor.advisor_name or advisor.name) if advisor else "Unknown",
            investor_risk_profile=req.investor_risk_profile,
            created_at=req.created_at,
            responded_at=req.responded_at,
        ))

    return responses


@router.patch(
    "/{request_id}/respond",
    response_model=RequestResponse,
    summary="Advisor accepts or rejects a request",
)
async def respond_to_request(
    request_id: str,
    payload: RespondRequestPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Advisor accepts or rejects an investor's request after viewing their risk profile."""
    if current_user.user_type != "advisor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only advisors can respond to requests",
        )

    result = await db.execute(
        select(AdvisorRequest).where(
            AdvisorRequest.id == request_id,
            AdvisorRequest.advisor_id == current_user.id,
        )
    )
    request = result.scalar_one_or_none()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if request.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Request already {request.status}",
        )

    request.status = payload.status
    request.advisor_response = payload.response_note
    request.responded_at = datetime.now(timezone.utc)

    db.add(request)
    await db.flush()

    inv_result = await db.execute(select(User).where(User.id == request.investor_id))
    investor = inv_result.scalar_one_or_none()

    return RequestResponse(
        id=request.id,
        investor_id=request.investor_id,
        advisor_id=request.advisor_id,
        status=request.status,
        message=request.message,
        advisor_response=request.advisor_response,
        investor_name=investor.name if investor else "Unknown",
        advisor_name=current_user.advisor_name or current_user.name,
        investor_risk_profile=request.investor_risk_profile,
        created_at=request.created_at,
        responded_at=request.responded_at,
    )


# ─── Chat Endpoints ─────────────────────────────────────────────────

@router.get(
    "/{request_id}/chat",
    response_model=list[ChatMessageResponse],
    summary="Get chat messages for an accepted request",
)
async def get_chat_messages(
    request_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve chat history between investor and advisor for an accepted request."""
    # Verify the request exists and user is a party
    result = await db.execute(
        select(AdvisorRequest).where(
            AdvisorRequest.id == request_id,
            or_(
                AdvisorRequest.investor_id == current_user.id,
                AdvisorRequest.advisor_id == current_user.id,
            ),
        )
    )
    request = result.scalar_one_or_none()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if request.status != "accepted":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chat is only available for accepted requests",
        )

    # Fetch messages
    msg_result = await db.execute(
        select(ChatMessage)
        .where(ChatMessage.request_id == request_id)
        .order_by(ChatMessage.created_at.asc())
    )
    messages = msg_result.scalars().all()

    # Mark unread messages as read
    for msg in messages:
        if msg.receiver_id == current_user.id and not msg.is_read:
            msg.is_read = True
            db.add(msg)
    await db.flush()

    responses = []
    for msg in messages:
        sender_result = await db.execute(select(User).where(User.id == msg.sender_id))
        sender = sender_result.scalar_one_or_none()
        responses.append(ChatMessageResponse(
            id=msg.id,
            request_id=msg.request_id,
            sender_id=msg.sender_id,
            receiver_id=msg.receiver_id,
            content=msg.content,
            message_type=msg.message_type,
            is_read=msg.is_read,
            created_at=msg.created_at,
            sender_name=sender.name if sender else "Unknown",
        ))

    return responses


@router.post(
    "/{request_id}/chat",
    response_model=ChatMessageResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Send a chat message",
)
async def send_message(
    request_id: str,
    payload: SendMessagePayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Send a message in an accepted advisor request's chat."""
    result = await db.execute(
        select(AdvisorRequest).where(
            AdvisorRequest.id == request_id,
            or_(
                AdvisorRequest.investor_id == current_user.id,
                AdvisorRequest.advisor_id == current_user.id,
            ),
        )
    )
    request = result.scalar_one_or_none()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if request.status != "accepted":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chat is only available for accepted requests",
        )

    # Determine receiver
    receiver_id = (
        request.advisor_id
        if current_user.id == request.investor_id
        else request.investor_id
    )

    message = ChatMessage(
        request_id=request_id,
        sender_id=current_user.id,
        receiver_id=receiver_id,
        content=payload.content,
        message_type="text",
    )
    db.add(message)
    await db.flush()
    await db.refresh(message)

    return ChatMessageResponse(
        id=message.id,
        request_id=message.request_id,
        sender_id=message.sender_id,
        receiver_id=message.receiver_id,
        content=message.content,
        message_type=message.message_type,
        is_read=message.is_read,
        created_at=message.created_at,
        sender_name=current_user.name,
    )


# ─── Call Endpoints ──────────────────────────────────────────────────

@router.post(
    "/{request_id}/call",
    response_model=CallSessionResponse,
    summary="Initiate a masked call session",
)
async def initiate_call(
    request_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Initiate a secure masked call — only available after advisor accepts."""
    result = await db.execute(
        select(AdvisorRequest).where(
            AdvisorRequest.id == request_id,
            or_(
                AdvisorRequest.investor_id == current_user.id,
                AdvisorRequest.advisor_id == current_user.id,
            ),
        )
    )
    request = result.scalar_one_or_none()
    if not request:
        raise HTTPException(status_code=404, detail="Request not found")

    if request.status != "accepted":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Calls are only available for accepted requests",
        )

    inv_result = await db.execute(select(User).where(User.id == request.investor_id))
    investor = inv_result.scalar_one_or_none()
    adv_result = await db.execute(select(User).where(User.id == request.advisor_id))
    advisor = adv_result.scalar_one_or_none()

    # Bridge both real numbers through the masked provider number — neither
    # party ever sees the other's actual mobile number.
    masked = await telephony_service.start_masked_call(
        session_id=request_id,
        investor_phone=investor.phone_number if investor else None,
        advisor_phone=advisor.phone_number if advisor else None,
    )

    # Create call session record
    session = CallSession(
        request_id=request_id,
        investor_id=request.investor_id,
        advisor_id=request.advisor_id,
        masked_number=masked.masked_number,
        status="initiated",
        provider=masked.provider,
        provider_call_sid=masked.provider_call_sid,
    )
    db.add(session)
    await db.flush()

    # Also log as a system message in chat
    call_log = ChatMessage(
        request_id=request_id,
        sender_id=current_user.id,
        receiver_id=(
            request.advisor_id
            if current_user.id == request.investor_id
            else request.investor_id
        ),
        content=f"📞 Call initiated via secure line {masked.masked_number}",
        message_type="call_log",
    )
    db.add(call_log)
    await db.flush()

    return CallSessionResponse(
        session_id=session.id,
        masked_number=masked.masked_number,
        expires_in=masked.expires_in,
    )
