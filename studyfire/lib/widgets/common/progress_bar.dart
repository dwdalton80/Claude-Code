import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';

class XpProgressBar extends StatelessWidget {
  final int current;
  final int max;
  final String? label;
  final double height;

  const XpProgressBar({
    super.key,
    required this.current,
    required this.max,
    this.label,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final progress = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTypography.labelSmall),
          const SizedBox(height: 4),
        ],
        Stack(
          children: [
            Container(
              height: height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              widthFactor: progress,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: AppColors.flameGradient,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.warmGold.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            '$current / $max XP',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class SessionProgressBar extends StatelessWidget {
  final double progress; // 0.0 to 1.0

  const SessionProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return AnimatedFractionallySizedBox(
      duration: const Duration(milliseconds: 400),
      widthFactor: progress.clamp(0.0, 1.0),
      alignment: Alignment.centerLeft,
      child: Container(
        height: 3,
        decoration: const BoxDecoration(
          gradient: AppColors.flameGradient,
        ),
      ),
    );
  }
}
