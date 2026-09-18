/// Dual-consent WebRTC call controller. Owns the signaling WebSocket
/// (ws://.../ws/advisor-requests/{requestId}) and the RTCPeerConnection.
/// A call is never bridged unilaterally — see the protocol documented in
/// backend/app/routers/call_signaling.py:
///
///   requestCall() -> call_request -> peer sees "incoming" -> acceptCall()
///   -> server creates CallSession, both sides get call_ready (exactly one
///   with youShouldOffer=true) -> WebRTC SDP/ICE exchange over this same
///   socket -> connected.
///
/// Uses a public Google STUN server only (no TURN) — sufficient for direct
/// peer connections on typical networks but calls behind symmetric NAT/
/// restrictive firewalls may fail to connect; a production deployment
/// would add a TURN relay.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/secure_storage.dart';

enum CallPhase { idle, requesting, incoming, connecting, connected, ended, declined, error }

class CallController extends ChangeNotifier {
  final String requestId;
  final Ref _ref;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallPhase phase = CallPhase.idle;
  String? sessionId;
  String? errorMessage;
  bool socketConnected = false;
  bool _iShouldOffer = false;

  MediaStream? get remoteStream => _remoteStream;

  CallController(this.requestId, this._ref) {
    _connectSocket();
  }

  Future<void> _connectSocket() async {
    final token = await _ref.read(secureStorageProvider).getAccessToken();
    if (token == null) return;
    final uri = Uri.parse(
      '${ApiEndpoints.wsBaseUrl}${ApiEndpoints.advisorRequestSocket(requestId)}?token=$token',
    );
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      socketConnected = true;
      notifyListeners();
      _sub = channel.stream.listen(
        _onMessage,
        onDone: () {
          socketConnected = false;
          notifyListeners();
        },
        onError: (_) {
          socketConnected = false;
          notifyListeners();
        },
      );
    } catch (_) {
      socketConnected = false;
      notifyListeners();
    }
  }

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> _onMessage(dynamic raw) async {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (data['type'] as String?) {
      case 'incoming_call_request':
        phase = CallPhase.incoming;
        notifyListeners();
        break;

      case 'call_declined':
        phase = CallPhase.declined;
        notifyListeners();
        break;

      case 'call_request_cancelled':
        phase = CallPhase.idle;
        notifyListeners();
        break;

      case 'call_ready':
        sessionId = data['session_id'] as String?;
        _iShouldOffer = data['you_should_offer'] as bool? ?? false;
        phase = CallPhase.connecting;
        notifyListeners();
        await _startWebRTC();
        break;

      case 'webrtc_offer':
        await _onRemoteOffer(data);
        break;

      case 'webrtc_answer':
        await _onRemoteAnswer(data);
        break;

      case 'webrtc_ice_candidate':
        await _onRemoteIceCandidate(data);
        break;

      case 'call_status':
        final status = data['status'] as String?;
        if (status == 'connected') {
          phase = CallPhase.connected;
        } else if (status == 'ended') {
          phase = CallPhase.ended;
          await _teardownMedia();
        }
        notifyListeners();
        break;

      case 'error':
        errorMessage = data['detail'] as String?;
        phase = CallPhase.error;
        notifyListeners();
        break;
    }
  }

  // ── Dual-consent handshake ──────────────────────────────────
  void requestCall() {
    phase = CallPhase.requesting;
    errorMessage = null;
    notifyListeners();
    _send({'type': 'call_request'});
  }

  void acceptCall() {
    _send({'type': 'call_accept'});
  }

  void declineCall() {
    _send({'type': 'call_decline'});
    phase = CallPhase.idle;
    notifyListeners();
  }

  void cancelCall() {
    _send({'type': 'call_cancel'});
    phase = CallPhase.idle;
    notifyListeners();
  }

  Future<void> endCall() async {
    if (sessionId != null) {
      _send({'type': 'call_end', 'session_id': sessionId});
    }
    phase = CallPhase.ended;
    notifyListeners();
    await _teardownMedia();
  }

  void resetToIdle() {
    phase = CallPhase.idle;
    errorMessage = null;
    notifyListeners();
  }

  // ── WebRTC media/session ─────────────────────────────────────
  Future<void> _startWebRTC() async {
    try {
      final pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      });
      _pc = pc;

      final localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
      _localStream = localStream;
      for (final track in localStream.getTracks()) {
        await pc.addTrack(track, localStream);
      }

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _send({
          'type': 'webrtc_ice_candidate',
          'session_id': sessionId,
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      };

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          notifyListeners();
        }
      };

      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _send({'type': 'call_connected', 'session_id': sessionId});
        }
      };

      if (_iShouldOffer) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        _send({
          'type': 'webrtc_offer',
          'session_id': sessionId,
          'sdp': offer.sdp,
          'sdp_type': offer.type,
        });
      }
    } catch (e) {
      errorMessage = 'Could not access the microphone. Check app permissions.';
      phase = CallPhase.error;
      notifyListeners();
    }
  }

  Future<void> _onRemoteOffer(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String, data['sdp_type'] as String));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _send({
      'type': 'webrtc_answer',
      'session_id': sessionId,
      'sdp': answer.sdp,
      'sdp_type': answer.type,
    });
  }

  Future<void> _onRemoteAnswer(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(data['sdp'] as String, data['sdp_type'] as String));
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.addCandidate(RTCIceCandidate(
      data['candidate'] as String?,
      data['sdp_mid'] as String?,
      data['sdp_mline_index'] as int?,
    ));
  }

  Future<void> _teardownMedia() async {
    await _localStream?.dispose();
    await _pc?.close();
    _localStream = null;
    _remoteStream = null;
    _pc = null;
    sessionId = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _teardownMedia();
    super.dispose();
  }
}

final callControllerProvider = ChangeNotifierProvider.family<CallController, String>((ref, requestId) {
  final controller = CallController(requestId, ref);
  ref.onDispose(() => controller.dispose());
  return controller;
});
