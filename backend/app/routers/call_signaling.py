"""
Dual-consent chat + WebRTC signaling.
One socket per (advisor_request, user) carries both live chat delivery and
call signaling. The call button stays meaningless until this handshake
completes — a call is NEVER bridged unilaterally:

  A --call_request--> [server]
  [server] --incoming_call_request--> B
  B --call_accept--> [server]
  [server] creates CallSession(status="ringing"), pushes call_ready to BOTH
  A and B then exchange WebRTC SDP/ICE relayed verbatim through this socket
  (webrtc_offer / webrtc_answer / webrtc_ice_candidate), each addressed to
  the other party only — the server never inspects payloads, it only routes
  them to whoever is connected to this request_id and isn't the sender.

REST endpoints (advisor_requests.py) remain the source of truth for chat
history and are unaffected; this socket only adds real-time delivery.
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.advisor_request import AdvisorRequest
from app.models.call_session import CallSession
from app.models.chat_message import ChatMessage
from app.models.user import User
from app.services.auth_service import decode_access_token
from app.services.call_signaling_service import manager

router = APIRouter(tags=["Call Signaling"])

# Message types relayed to the peer verbatim, no server-side interpretation.
_RELAYED_TYPES = {"webrtc_offer", "webrtc_answer", "webrtc_ice_candidate"}


async def _authenticate(token: str) -> Optional[str]:
    payload = decode_access_token(token)
    if not payload:
        return None
    return payload.get("sub")


async def _authorize(request_id: str, user_id: str) -> Optional[AdvisorRequest]:
    async with AsyncSessionLocal() as db:
        req = (
            await db.execute(select(AdvisorRequest).where(AdvisorRequest.id == request_id))
        ).scalar_one_or_none()
        if not req or req.status != "accepted":
            return None
        if user_id not in (req.investor_id, req.advisor_id):
            return None
        return req


async def _persist_chat_message(request_id: str, sender_id: str, receiver_id: str, content: str) -> dict:
    async with AsyncSessionLocal() as db:
        sender = (await db.execute(select(User).where(User.id == sender_id))).scalar_one_or_none()
        msg = ChatMessage(
            request_id=request_id, sender_id=sender_id, receiver_id=receiver_id,
            content=content, message_type="text",
        )
        db.add(msg)
        await db.commit()
        await db.refresh(msg)
        return {
            "id": msg.id, "request_id": msg.request_id, "sender_id": msg.sender_id,
            "receiver_id": msg.receiver_id, "content": msg.content,
            "message_type": msg.message_type, "is_read": msg.is_read,
            "created_at": msg.created_at.isoformat(),
            "sender_name": sender.name if sender else None,
        }


async def _create_call_session(req: AdvisorRequest) -> CallSession:
    async with AsyncSessionLocal() as db:
        session = CallSession(
            request_id=req.id, investor_id=req.investor_id, advisor_id=req.advisor_id,
            masked_number="In-app WebRTC call", status="ringing", provider="webrtc",
        )
        db.add(session)
        await db.commit()
        await db.refresh(session)
        return session


async def _set_call_status(session_id: str, status: str) -> Optional[CallSession]:
    async with AsyncSessionLocal() as db:
        session = (
            await db.execute(select(CallSession).where(CallSession.id == session_id))
        ).scalar_one_or_none()
        if not session or session.status == "ended":
            return session
        session.status = status
        if status == "ended":
            session.ended_at = datetime.now(timezone.utc)
            # SQLite drops tzinfo on read-back even for DateTime(timezone=True)
            # columns — started_at always came from datetime.now(timezone.utc)
            # at insert time, so a naive value here is UTC, not local time.
            started_at = session.started_at
            if started_at.tzinfo is None:
                started_at = started_at.replace(tzinfo=timezone.utc)
            session.duration_seconds = int((session.ended_at - started_at).total_seconds())
        await db.commit()
        await db.refresh(session)
        return session


async def _log_call_end(request_id: str, ender_id: str, peer_id: str, duration_seconds: int) -> None:
    async with AsyncSessionLocal() as db:
        db.add(ChatMessage(
            request_id=request_id, sender_id=ender_id, receiver_id=peer_id,
            content=f"Call ended · {duration_seconds}s", message_type="call_log",
        ))
        await db.commit()


@router.websocket("/ws/advisor-requests/{request_id}")
async def advisor_request_socket(websocket: WebSocket, request_id: str, token: str = Query(...)):
    await websocket.accept()

    user_id = await _authenticate(token)
    if not user_id:
        await websocket.send_json({"type": "error", "detail": "Invalid or expired token"})
        await websocket.close(code=4401)
        return

    req = await _authorize(request_id, user_id)
    if not req:
        await websocket.send_json({"type": "error", "detail": "Not authorized for this conversation"})
        await websocket.close(code=4403)
        return

    peer_id = req.advisor_id if user_id == req.investor_id else req.investor_id

    await manager.connect(request_id, user_id, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type")

            if msg_type == "chat_message":
                content = (data.get("content") or "").strip()
                if not content:
                    continue
                saved = await _persist_chat_message(request_id, user_id, peer_id, content)
                await websocket.send_json({"type": "chat_message", "message": saved})
                await manager.send_to_user(request_id, peer_id, {"type": "chat_message", "message": saved})

            elif msg_type == "call_request":
                manager.set_pending_call(request_id, user_id)
                await websocket.send_json({"type": "call_request_sent"})
                delivered = await manager.send_to_user(
                    request_id, peer_id, {"type": "incoming_call_request", "from_user_id": user_id}
                )
                if not delivered:
                    await websocket.send_json({
                        "type": "call_request_pending",
                        "detail": "The other party is currently offline",
                    })

            elif msg_type == "call_accept":
                initiator_id = manager.get_pending_call_initiator(request_id)
                if initiator_id != peer_id:
                    await websocket.send_json({"type": "error", "detail": "No pending call request to accept"})
                    continue
                manager.clear_pending_call(request_id)
                session = await _create_call_session(req)
                await websocket.send_json({
                    "type": "call_ready", "session_id": session.id, "you_should_offer": False,
                })
                await manager.send_to_user(request_id, peer_id, {
                    "type": "call_ready", "session_id": session.id, "you_should_offer": True,
                })

            elif msg_type == "call_decline":
                if manager.get_pending_call_initiator(request_id) == peer_id:
                    manager.clear_pending_call(request_id)
                    await manager.send_to_user(request_id, peer_id, {"type": "call_declined"})

            elif msg_type == "call_cancel":
                if manager.get_pending_call_initiator(request_id) == user_id:
                    manager.clear_pending_call(request_id)
                    await manager.send_to_user(request_id, peer_id, {"type": "call_request_cancelled"})

            elif msg_type in _RELAYED_TYPES:
                await manager.send_to_user(request_id, peer_id, data)

            elif msg_type == "call_connected":
                session_id = data.get("session_id")
                if session_id:
                    await _set_call_status(session_id, "connected")
                    payload = {"type": "call_status", "status": "connected", "session_id": session_id}
                    await websocket.send_json(payload)
                    await manager.send_to_user(request_id, peer_id, payload)

            elif msg_type == "call_end":
                session_id = data.get("session_id")
                if session_id:
                    session = await _set_call_status(session_id, "ended")
                    duration = session.duration_seconds if session else 0
                    await _log_call_end(request_id, user_id, peer_id, duration)
                    payload = {
                        "type": "call_status", "status": "ended",
                        "session_id": session_id, "duration_seconds": duration,
                    }
                    await websocket.send_json(payload)
                    await manager.send_to_user(request_id, peer_id, payload)

    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect(request_id, user_id)
        await manager.send_to_user(request_id, peer_id, {"type": "peer_disconnected"})
