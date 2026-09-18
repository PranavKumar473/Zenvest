"""
In-memory WebSocket connection registry + dual-consent call state.
Single-process MVP: fine for the SQLite/single-uvicorn-worker dev deployment
this project already runs; a multi-worker production deployment would need
this backed by Redis pub/sub instead.

Dual-consent rule: a call is never bridged unilaterally. One party sends
call_request, the other must send call_accept before a CallSession is
created and WebRTC signaling begins — see app/routers/call_signaling.py.
"""
from typing import Optional

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self):
        self._connections: dict[str, dict[str, WebSocket]] = {}
        self._pending_call_initiator: dict[str, str] = {}  # request_id -> user_id

    async def connect(self, request_id: str, user_id: str, websocket: WebSocket) -> None:
        self._connections.setdefault(request_id, {})[user_id] = websocket

    def disconnect(self, request_id: str, user_id: str) -> None:
        conns = self._connections.get(request_id)
        if conns:
            conns.pop(user_id, None)
            if not conns:
                self._connections.pop(request_id, None)
        if self._pending_call_initiator.get(request_id) == user_id:
            self._pending_call_initiator.pop(request_id, None)

    async def send_to_user(self, request_id: str, user_id: str, message: dict) -> bool:
        ws = self._connections.get(request_id, {}).get(user_id)
        if ws is None:
            return False
        await ws.send_json(message)
        return True

    def is_online(self, request_id: str, user_id: str) -> bool:
        return user_id in self._connections.get(request_id, {})

    def set_pending_call(self, request_id: str, initiator_id: str) -> None:
        self._pending_call_initiator[request_id] = initiator_id

    def get_pending_call_initiator(self, request_id: str) -> Optional[str]:
        return self._pending_call_initiator.get(request_id)

    def clear_pending_call(self, request_id: str) -> None:
        self._pending_call_initiator.pop(request_id, None)


manager = ConnectionManager()
