import 'investor.dart';

/// Communication-session domain models — mirror backend AdvisorRequest,
/// ChatMessage, and CallSession (see backend/app/models/*.py).

enum ConnectRequestStatus { pending, accepted, rejected }

ConnectRequestStatus connectRequestStatusFromString(String value) {
  switch (value) {
    case 'accepted':
      return ConnectRequestStatus.accepted;
    case 'rejected':
      return ConnectRequestStatus.rejected;
    default:
      return ConnectRequestStatus.pending;
  }
}

/// A "Connect Request" — the mandatory request-first gate before an investor
/// and advisor can chat or call. Carries a snapshot of the investor's risk
/// profile so the advisor can screen before accepting.
class ConnectRequest {
  final String id;
  final String investorId;
  final String advisorId;
  final ConnectRequestStatus status;
  final String? message;
  final String? advisorResponse;
  final String? investorName;
  final String? advisorName;
  final InvestorRiskProfile? investorRiskProfile;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const ConnectRequest({
    required this.id,
    required this.investorId,
    required this.advisorId,
    required this.status,
    this.message,
    this.advisorResponse,
    this.investorName,
    this.advisorName,
    this.investorRiskProfile,
    required this.createdAt,
    this.respondedAt,
  });

  bool get isAccepted => status == ConnectRequestStatus.accepted;

  factory ConnectRequest.fromJson(Map<String, dynamic> json) {
    return ConnectRequest(
      id: json['id'] as String,
      investorId: json['investor_id'] as String,
      advisorId: json['advisor_id'] as String,
      status: connectRequestStatusFromString(json['status'] as String? ?? 'pending'),
      message: json['message'] as String?,
      advisorResponse: json['advisor_response'] as String?,
      investorName: json['investor_name'] as String?,
      advisorName: json['advisor_name'] as String?,
      investorRiskProfile: json['investor_risk_profile'] != null
          ? InvestorRiskProfile.fromJson(json['investor_risk_profile'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      respondedAt: json['responded_at'] != null ? DateTime.parse(json['responded_at'] as String) : null,
    );
  }
}

enum ChatMessageType { text, system, callLog }

ChatMessageType chatMessageTypeFromString(String value) {
  switch (value) {
    case 'system':
      return ChatMessageType.system;
    case 'call_log':
      return ChatMessageType.callLog;
    default:
      return ChatMessageType.text;
  }
}

/// A single message within an accepted ConnectRequest's chat thread.
/// Persisted indefinitely server-side for the compliance audit trail.
class ChatMessage {
  final String id;
  final String requestId;
  final String senderId;
  final String receiverId;
  final String content;
  final ChatMessageType type;
  final bool isRead;
  final DateTime createdAt;
  final String? senderName;

  const ChatMessage({
    required this.id,
    required this.requestId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.senderName,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      content: json['content'] as String? ?? '',
      type: chatMessageTypeFromString(json['message_type'] as String? ?? 'text'),
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderName: json['sender_name'] as String?,
    );
  }
}

/// A masked, recorded call bridge between investor and advisor — only ever
/// created for an accepted ConnectRequest. Neither party's real mobile
/// number is exposed; the backend telephony provider bridges both real
/// numbers through `maskedNumber`.
class CommunicationCallSession {
  final String sessionId;
  final String maskedNumber;
  final int expiresInSeconds;

  const CommunicationCallSession({
    required this.sessionId,
    required this.maskedNumber,
    required this.expiresInSeconds,
  });

  factory CommunicationCallSession.fromJson(Map<String, dynamic> json) {
    return CommunicationCallSession(
      sessionId: json['session_id'] as String,
      maskedNumber: json['masked_number'] as String,
      expiresInSeconds: (json['expires_in'] as num?)?.toInt() ?? 600,
    );
  }
}
