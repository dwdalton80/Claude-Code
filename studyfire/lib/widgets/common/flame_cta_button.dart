import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';

class FlameCTAButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? height;
  final EdgeInsets? padding;

  const FlameCTAButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        width: double.infinity,
        height: height ?? 56,
        padding: padding,
        decoration: BoxDecoration(
          gradient: onPressed == null || isLoading
              ? null
              : AppColors.flameCTAGradient,
          color: onPressed == null || isLoading ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed != null && !isLoading
              ? [
                  BoxShadow(
                    color: AppColors.flameOrange.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(label, style: AppTypography.button),
        ),
      ),
    );
  }
}

class FlameSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const FlameSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        side: const BorderSide(color: AppColors.warmGold, width: 1.5),
        foregroundColor: AppColors.warmGold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: AppTypography.buttonSmall.copyWith(color: AppColors.warmGold)),
    );
  }
}

class SkipTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const SkipTextButton({super.key, this.label = 'Skip', required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
