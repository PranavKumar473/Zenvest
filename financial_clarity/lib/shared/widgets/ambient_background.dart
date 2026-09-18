/// Ambient blurred-circle backdrop, extracted from the pattern originally
/// inlined in AdvisorProfileScreen so new screens (fund directory, top-5,
/// fund detail) can reuse the same glassmorphism treatment consistently.
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class AmbientBackground extends StatelessWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 250,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withOpacity(0.05),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
