import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/animated_card.dart';

class CallConnectingScreen extends ConsumerStatefulWidget {
  final String advisorId;
  final String advisorName;
  final String sessionId;
  final String maskedNumber;

  const CallConnectingScreen({
    super.key,
    required this.advisorId,
    required this.advisorName,
    required this.sessionId,
    required this.maskedNumber,
  });

  @override
  ConsumerState<CallConnectingScreen> createState() => _CallConnectingScreenState();
}

class _CallConnectingScreenState extends ConsumerState<CallConnectingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String _callStatus = 'Connecting secure line...';
  Timer? _statusTimer;
  Timer? _countdownTimer;
  int _secondsRemaining = 600; // 10 minutes
  int _elapsedCallSeconds = 0;
  bool _isCallConnected = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startCallSimulation();
  }

  void _startCallSimulation() {
    // 1. Simulate Connecting -> Ringing (after 2.5 seconds)
    _statusTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _callStatus = 'Ringing...';
        });
      }

      // 2. Simulate Ringing -> Connected (after 4 more seconds)
      _statusTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _callStatus = 'Connected';
            _isCallConnected = true;
          });
          _startCallTimer();
        }
      });
    });

    // 3. Start Session Timeout Countdown (runs from the beginning)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;
          } else {
            _endCall();
          }

          if (_isCallConnected) {
            _elapsedCallSeconds++;
          }
        });
      }
    });
  }

  void _startCallTimer() {
    // Timer is driven by the countdown periodic timer
  }

  void _endCall() {
    _statusTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Secure session ended.'),
          backgroundColor: AppColors.ink,
        ),
      );
      context.pop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink, // Premium dark screen for calls
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Eyebrow secure banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'SECURE END-TO-END SESSION',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 10,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),

              // Advisor Details
              Text(
                widget.advisorName,
                style: AppTypography.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isCallConnected 
                    ? 'Connected — ${_formatTime(_elapsedCallSeconds)}' 
                    : _callStatus,
                style: AppTypography.bodyLarge.copyWith(
                  color: _isCallConnected ? AppColors.success : Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 60),

              // Calling Waves / Pulsing Icon
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Radial wave rings
                      ...List.generate(3, (index) {
                        return AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final delay = index * 0.33;
                            double progress = _pulseController.value - delay;
                            if (progress < 0) progress += 1.0;
                            
                            // Let the wave fade out and expand
                            final scale = 1.0 + (progress * 1.5);
                            final opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.25;

                            return Container(
                              width: 140,
                              height: 140,
                              transform: Matrix4.identity()..scale(scale),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isCallConnected 
                                    ? AppColors.success.withOpacity(opacity) 
                                    : AppColors.primary.withOpacity(opacity),
                              ),
                            );
                          },
                        );
                      }),
                      
                      // Central Phone Button Icon
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isCallConnected ? AppColors.success : AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: (_isCallConnected ? AppColors.success : AppColors.primary).withOpacity(0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.phone_in_talk_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Masked Virtual Number Info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.04),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    Text(
                      'SECURE LINE NUMBER',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.maskedNumber,
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white, 
                        fontFamily: 'JetBrains Mono',
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This call runs via a masked virtual bridge to protect your privacy. Session ID expires in ${_formatTime(_secondsRemaining)}.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.5),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Disconnect Action Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(24),
                  elevation: 0,
                ),
                onPressed: _endCall,
                child: const Icon(
                  Icons.call_end_rounded,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
