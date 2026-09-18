import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/presentation/auth_controller.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/error_widget.dart';
import '../domain/call_controller.dart';
import 'in_call_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String requestId;
  final String peerName;

  const ChatScreen({
    super.key,
    required this.requestId,
    required this.peerName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final List<dynamic> _messages = [];
  bool _isLoading = true;
  String? _error;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    // Setup polling every 3 seconds to simulate real-time chat for MVP
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchMessages(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/advisor-requests/${widget.requestId}/chat');
      if (mounted) {
        final List<dynamic> fetched = response.data;
        
        bool isNew = fetched.length != _messages.length;
        
        setState(() {
          _messages.clear();
          _messages.addAll(fetched);
          _isLoading = false;
        });

        if (isNew && _scrollController.hasClients) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = 'Failed to load messages.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      final dio = ref.read(dioProvider);
      await dio.post('/advisor-requests/${widget.requestId}/chat', data: {
        'content': text,
      });
      _fetchMessages(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _incomingDialogShowing = false;

  void _onCallPhaseChanged(CallController controller) {
    switch (controller.phase) {
      case CallPhase.incoming:
        _showIncomingCallDialog(controller);
        break;
      case CallPhase.connecting:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InCallScreen(requestId: widget.requestId, peerName: widget.peerName),
          ),
        );
        break;
      case CallPhase.declined:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call declined.'), backgroundColor: AppColors.warning),
        );
        controller.resetToIdle();
        break;
      case CallPhase.error:
        if (controller.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(controller.errorMessage!), backgroundColor: AppColors.error),
          );
        }
        break;
      default:
        break;
    }
  }

  Future<void> _showIncomingCallDialog(CallController controller) async {
    if (_incomingDialogShowing) return;
    _incomingDialogShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('${widget.peerName} wants to start a secure voice call.'),
        actions: [
          TextButton(
            onPressed: () {
              controller.declineCall();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () {
              controller.acceptCall();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    _incomingDialogShowing = false;
  }

  void _onCallButtonPressed(CallController controller) {
    switch (controller.phase) {
      case CallPhase.idle:
      case CallPhase.declined:
      case CallPhase.ended:
      case CallPhase.error:
        controller.requestCall();
        break;
      case CallPhase.requesting:
        controller.cancelCall();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final myUserId = authState.userId;

    final callController = ref.watch(callControllerProvider(widget.requestId));
    ref.listen<CallController>(callControllerProvider(widget.requestId), (previous, next) {
      if (previous?.phase != next.phase) _onCallPhaseChanged(next);
    });

    final callButtonBusy = callController.phase == CallPhase.requesting ||
        callController.phase == CallPhase.connecting ||
        callController.phase == CallPhase.connected;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
            Text(
              callController.socketConnected ? 'Secure Line' : 'Connecting…',
              style: AppTypography.bodySmall.copyWith(
                color: callController.socketConnected ? AppColors.success : AppColors.inkMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              callButtonBusy ? Icons.phone_forwarded_rounded : Icons.phone_in_talk_rounded,
              color: callController.socketConnected ? AppColors.primary : AppColors.inkMuted,
            ),
            tooltip: callController.phase == CallPhase.requesting
                ? 'Cancel call request'
                : 'Request a dual-consent voice call',
            onPressed: callController.socketConnected ? () => _onCallButtonPressed(callController) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Compliance Recording Banner
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All calls & chats are securely recorded for compliance.',
                    style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? LoadingShimmer.list(count: 4, itemHeight: 80)
                : _error != null
                    ? AppErrorWidget(message: _error!, onRetry: () => _fetchMessages())
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg['sender_id'] == myUserId;
                              final type = msg['message_type'] as String;

                              if (type == 'call_log') {
                                return _buildCallLogBubble(msg);
                              }

                              return _buildChatBubble(msg, isMe);
                            },
                          ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(dynamic msg, bool isMe) {
    final Alignment alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final Color bubbleColor = isMe ? AppColors.primary : AppColors.surface;
    final Color textColor = isMe ? Colors.white : AppColors.ink;
    final date = DateTime.parse(msg['created_at']).toLocal();
    final timeStr = DateFormat.jm().format(date);

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          border: isMe ? null : Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg['content'] ?? '',
              style: AppTypography.bodyMedium.copyWith(color: textColor),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 8,
                    color: isMe ? Colors.white70 : AppColors.inkMuted,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all_rounded,
                    size: 12,
                    color: msg['is_read'] == true ? Colors.lightBlueAccent : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogBubble(dynamic msg) {
    final date = DateTime.parse(msg['created_at']).toLocal();
    final timeStr = DateFormat.jm().format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_callback_rounded, color: AppColors.success, size: 16),
            const SizedBox(width: 8),
            Text(
              msg['content'] ?? '',
              style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              timeStr,
              style: TextStyle(fontSize: 8, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.canvas,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.inkMuted),
          const SizedBox(height: 12),
          Text('No messages yet', style: AppTypography.bodyLarge),
          const SizedBox(height: 4),
          Text(
            'Start typing below to chat securely.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}
