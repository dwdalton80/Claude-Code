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
///
/// [featureName] is the feature the user hit a limit on — shown as the headline.
/// [limitMessage] describes the specific limit (e.g. "You've used your 3 free AI questions today").
void showPaywallSheet(BuildContext context, {String? featureName, String? limitMessage}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => _PaywallBottomSheet(featureName: featureName, limitMessage: limitMessage),
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
  final String? limitMessage;

  const _PaywallBottomSheet({this.featureName, this.limitMessage});

  @override
  Widget build(BuildContext context) {
    // Determine which feature to highlight based on featureName
    final highlights = _highlightsFor(featureName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const Text('⚡', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),

          Text(
            featureName != null ? 'Unlock $featureName' : 'Unlock StudyFire Premium',
            style: AppTypography.displaySmall,
            textAlign: TextAlign.center,
          ),

          if (limitMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warmGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
              ),
              child: Text(
                limitMessage!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Feature list
          ...highlights.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(h.$1, size: 16, color: AppColors.warmGold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.$2, style: AppTypography.labelSmall.copyWith(color: AppColors.warmWhite)),
                      Text(h.$3, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          )),

          const SizedBox(height: 8),
          Text(
            '\$3.99/month · \$29.99/year · \$19.99 student',
            style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FlameCTAButton(
            label: 'Upgrade — \$3.99/mo',
            onPressed: () {
              Navigator.pop(context);
              // TODO: RevenueCat.presentPaywall()
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Not now', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // Returns (icon, title, subtitle) tuples — highlights the relevant feature first
  List<(IconData, String, String)> _highlightsFor(String? feature) {
    const all = [
      (Icons.psychology_outlined,     'Unlimited AI Questions',    'Get as many study questions as you want'),
      (Icons.menu_book_outlined,       'All Bible Versions',        'NIV, CSB, ESV, NASB and more'),
      (Icons.translate_outlined,       'Greek & Hebrew Explorer',   'Dig into original language word studies'),
      (Icons.ac_unit_outlined,         'Streak Freeze',             'Protect your streak for up to 3 days'),
    ];

    if (feature == null) return all;

    final f = feature.toLowerCase();
    final List<(IconData, String, String)> sorted = [...all];

    // Bubble the relevant feature to top
    if (f.contains('ai') || f.contains('question')) {
      sorted.sort((a, b) => a.$2.contains('AI') ? -1 : 1);
    } else if (f.contains('version') || f.contains('bible')) {
      sorted.sort((a, b) => a.$2.contains('Bible') ? -1 : 1);
    } else if (f.contains('greek') || f.contains('hebrew') || f.contains('word')) {
      sorted.sort((a, b) => a.$2.contains('Greek') ? -1 : 1);
    } else if (f.contains('streak') || f.contains('freeze')) {
      sorted.sort((a, b) => a.$2.contains('Streak') ? -1 : 1);
    }

    return sorted;
  }
}
