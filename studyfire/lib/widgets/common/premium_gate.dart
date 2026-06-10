import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import 'flame_cta_button.dart';

/// Wraps a child widget with a paywall lock when isPremium is false.
///
/// Usage:
///   PremiumGate(
///     isPremium: user.isPremium,
///     featureName: 'AI Study Mode',
///     child: AiStudyScreen(...),
///   )
class PremiumGate extends StatelessWidget {
  final bool isPremium;
  final String featureName;
  final Widget child;
  final VoidCallback? onUpgradeTap;

  const PremiumGate({
    super.key,
    required this.isPremium,
    required this.featureName,
    required this.child,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isPremium) return child;
    return _PaywallScreen(featureName: featureName, onUpgradeTap: onUpgradeTap);
  }
}

/// Inline paywall prompt for bottom sheets and cards.
class PremiumInlineBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onUpgradeTap;

  const PremiumInlineBanner({
    super.key,
    required this.message,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warmGold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.warmGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite),
            ),
          ),
          if (onUpgradeTap != null)
            TextButton(
              onPressed: onUpgradeTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.warmGold,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Text('Unlock', style: AppTypography.labelSmall),
            ),
        ],
      ),
    );
  }
}

/// Shows a paywall bottom sheet from anywhere.
void showPaywallSheet(BuildContext context, {String? featureName}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PaywallBottomSheet(featureName: featureName),
  );
}

class _PaywallScreen extends StatelessWidget {
  final String featureName;
  final VoidCallback? onUpgradeTap;

  const _PaywallScreen({required this.featureName, this.onUpgradeTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(featureName),
        leading: const BackButton(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔒', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 24),
            Text(featureName, style: AppTypography.displaySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'This feature is available with StudyFire Premium.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '\$3.99/month  ·  \$29.99/year  ·  \$19.99 student',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FlameCTAButton(
              label: 'Unlock Premium',
              onPressed: onUpgradeTap ?? () {
                // TODO: RevenueCat.presentPaywall()
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Not now', style: AppTypography.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaywallBottomSheet extends StatelessWidget {
  final String? featureName;

  const _PaywallBottomSheet({this.featureName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (featureName != null) ...[
            Text(
              '🔒 $featureName',
              style: AppTypography.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Unlock unlimited AI study questions, all Bible versions, Greek/Hebrew Explorer, streak freeze, and more.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '\$3.99/month · \$29.99/year · \$19.99 student',
            style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 24),
          FlameCTAButton(
            label: 'Unlock Premium — \$3.99/mo',
            onPressed: () {
              Navigator.pop(context);
              // TODO: RevenueCat.presentPaywall()
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now', style: AppTypography.bodySmall),
          ),
        ],
      ),
    );
  }
}
