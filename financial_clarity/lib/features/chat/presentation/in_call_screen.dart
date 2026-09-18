/// Minimal in-call UI, driven entirely by CallController.phase. Shown while
/// phase is connecting/connected; pops itself when the call ends.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../domain/call_controller.dart';

class InCallScreen extends ConsumerStatefulWidget {
  final String requestId;
  final String peerName;

  const InCallScreen({super.key, required this.requestId, required this.peerName});

  @override
  ConsumerState<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends ConsumerState<InCallScreen> {
  Timer? _ticker;
  int _elapsedSeconds = 0;

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(callControllerProvider(widget.requestId));

    ref.listen<CallController>(callControllerProvider(widget.requestId), (previous, next) {
      if (next.phase == CallPhase.ended || next.phase == CallPhase.declined || next.phase == CallPhase.error) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });

    if (controller.phase == CallPhase.connected) {
      _startTicker();
    }

    final statusLabel = switch (controller.phase) {
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => _elapsedLabel,
      _ => 'Call ending…',
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 40),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      child: Text(
                        widget.peerName.isNotEmpty ? widget.peerName[0] : '?',
                        style: AppTypography.displayMedium.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(widget.peerName, style: AppTypography.titleLarge.copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(statusLabel, style: AppTypography.bodyMedium.copyWith(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      'Secure in-app call · WebRTC',
                      style: AppTypography.labelSmall.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: () => controller.endCall(),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
