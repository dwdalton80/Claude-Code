import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/progress_bar.dart';
import '../../widgets/gamification/xp_burst.dart';
import 'package:go_router/go_router.dart';
import '../../app.dart';
import 'spark_session_screen.dart';

enum SessionLength { spark, short, deep }

class QuestScreen extends ConsumerStatefulWidget {
  const QuestScreen({super.key});

  @override
  ConsumerState<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends ConsumerState<QuestScreen> {
  SessionLength _sessionLength = SessionLength.spark;

  // TODO: wire to Firestore/provider
  static const _mockPassage = 'Romans 8:28';
  static const _streak = 7;
  static const _dailyXp = 45;
  static const _dailyXpGoal = 100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(flex: 8, child: _QuestCard(
                  passage: _mockPassage,
                  xpReward: _xpForLength(_sessionLength),
                  sessionLength: _sessionLength,
                  onLengthChanged: (l) => setState(() => _sessionLength = l),
                  onStart: _startSession,
                )),
                Expanded(flex: 2, child: _StatsBar(
                  streak: _streak,
                  dailyXp: _dailyXp,
                  dailyXpGoal: _dailyXpGoal,
                )),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 80,
              child: _RandomSparkFAB(onTap: _randomSpark),
            ),
          ],
        ),
      ),
    );
  }

  int _xpForLength(SessionLength l) => switch (l) {
        SessionLength.spark => XpRewards.completeSparkSession,
        SessionLength.short => XpRewards.completeShortSession,
        SessionLength.deep => XpRewards.completeDeepSession,
      };

void _startSession() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SparkSessionScreen(
          passageId: 'rom_8_28',
          reference: 'Romans 8:28',
          version: 'kjv',
        ),
      ),
    );
  }

  void _randomSpark() {
    final options = [
      ['jhn', 3, 16],
      ['rom', 8, 28],
      ['psa', 23, 1],
      ['php', 4, 13],
      ['isa', 40, 31],
      ['jer', 29, 11],
      ['pro', 3, 5],
      ['mat', 5, 3],
    ];
    final pick = options[DateTime.now().millisecond % options.length];
    final uid = ref.read(authStreamProvider).valueOrNull?.uid ?? '';
    context.push('/reader', extra: {
      'book': pick[0] as String,
      'chapter': pick[1] as int,
      'version': 'kjv',
    });
  }
}

class _QuestCard extends StatelessWidget {
  final String passage;
  final int xpReward;
  final SessionLength sessionLength;
  final ValueChanged<SessionLength> onLengthChanged;
  final VoidCallback onStart;

  const _QuestCard({
    required this.passage,
    required this.xpReward,
    required this.sessionLength,
    required this.onLengthChanged,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surface),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "TODAY'S QUEST",
                    style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Beginner', style: AppTypography.labelSmall),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              passage,
              style: AppTypography.displayMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _XpBadge(xp: xpReward),
                const SizedBox(width: 12),
                _TimeBadge(sessionLength: sessionLength),
              ],
            ),
            const SizedBox(height: 20),
            _SessionToggle(
              selected: sessionLength,
              onChanged: onLengthChanged,
            ),
            const Spacer(),
            FlameCTAButton(
              label: 'Start Quest  ⚡',
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _XpBadge extends StatelessWidget {
  final int xp;
  const _XpBadge({required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warmGold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚡', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$xp XP',
            style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
          ),
        ],
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  final SessionLength sessionLength;
  const _TimeBadge({required this.sessionLength});

  @override
  Widget build(BuildContext context) {
    final label = switch (sessionLength) {
      SessionLength.spark => '~90 sec',
      SessionLength.short => '~5 min',
      SessionLength.deep => '~10 min',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: AppTypography.labelSmall),
    );
  }
}

class _SessionToggle extends StatelessWidget {
  final SessionLength selected;
  final ValueChanged<SessionLength> onChanged;

  const _SessionToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: SessionLength.values.map((l) {
          final isSelected = l == selected;
          final label = switch (l) {
            SessionLength.spark => 'Spark',
            SessionLength.short => 'Short',
            SessionLength.deep => 'Deep',
          };
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.warmGold : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int streak;
  final int dailyXp;
  final int dailyXpGoal;

  const _StatsBar({
    required this.streak,
    required this.dailyXp,
    required this.dailyXpGoal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          StreakDisplay(streak: streak),
          const SizedBox(height: 10),
          XpProgressBar(
            current: dailyXp,
            max: dailyXpGoal,
            label: 'Daily XP',
          ),
        ],
      ),
    );
  }
}

class _RandomSparkFAB extends StatelessWidget {
  final VoidCallback onTap;
  const _RandomSparkFAB({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppColors.flameCTAGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.flameOrange.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text('🔥', style: TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
