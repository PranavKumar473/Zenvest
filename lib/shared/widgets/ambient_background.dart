/// Slow-drifting, blurred gradient blobs — a "living" premium background
/// for hero/journey screens (auth, onboarding). No external image or video
/// asset: pure Flutter gradients + BackdropFilter blur, animated with a
/// gentle continuous loop so it reads as alive without being distracting.
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class AmbientBackground extends StatefulWidget {
  final Widget child;
  final List<Color>? gradientColors;

  const AmbientBackground({
    super.key,
    required this.child,
    this.gradientColors,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _drift(double t, double phaseOffset, double amplitude) {
    final phase = (t + phaseOffset) * 2 * pi;
    return sin(phase) * amplitude;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.gradientColors ??
                    const [AppColors.ambientCream, AppColors.canvas],
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              children: [
                _blob(
                  top: -90 + _drift(t, 0.0, 26),
                  right: -70 + _drift(t, 0.3, 20),
                  size: 240,
                  color: AppColors.primary.withOpacity(0.14),
                ),
                _blob(
                  bottom: -110 + _drift(t, 0.55, 30),
                  left: -90 + _drift(t, 0.15, 22),
                  size: 280,
                  color: AppColors.ambientPeach.withOpacity(0.60),
                ),
                _blob(
                  top: 260 + _drift(t, 0.75, 34),
                  left: -60 + _drift(t, 0.4, 18),
                  size: 160,
                  color: AppColors.primaryLight.withOpacity(0.10),
                ),
              ],
            );
          },
        ),
        widget.child,
      ],
    );
  }

  Widget _blob({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
