import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/xp_service.dart';
import '../../core/services/streak_service.dart';
import '../../core/constants/xp_rewards.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/gamification/xp_burst.dart';

enum _SparkStep { verse, question, celebration }

class SparkScreen extends ConsumerStatefulWidget {
  final SparkQuestion question;
  final String uid;

  const SparkScreen({super.key, required this.question, required this.uid});

  @override
  ConsumerState<SparkScreen> createState() => _SparkScreenState();
}

class _SparkScreenState extends ConsumerState<SparkScreen> {
  _SparkStep _step = _SparkStep.verse;
  final _answerCtrl = TextEditingController();
  bool _submitting = false;
  int _totalXpEarned = 0;
  int _newStreak = 0;
  bool _showXpBurst = false;
  int _burstAmount = 0;

  final _xpService = XpService();
  final _streakService = StreakService();

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: Stack(
        children: [
          // Progress bar at very top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: LinearProgressIndicator(
                value: switch (_step) {
                  _SparkStep.verse => 0.33,
                  _SparkStep.question => 0.66,
                  _SparkStep.celebration => 1.0,
                },
                minHeight: 3,
                backgroundColor: AppColors.surface,
                valueColor: const AlwaysStoppedAnimation(AppColors.warmGold),
              ),
            ),
          ),
          // Content — no nav chrome
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: switch (_step) {
                  _SparkStep.verse => _VerseStep(
                      question: widget.question,
                      onRead: _onVerseRead,
                    ),
                  _SparkStep.question => _QuestionStep(
                      question: widget.question.question,
                      controller: _answerCtrl,
                      submitting: _submitting,
                      onSubmit: _onAnswerSubmit,
                      onSkip: _onAnswerSubmit,
                    ),
                  _SparkStep.celebration => _CelebrationStep(
                      xpEarned: _totalXpEarned,
                      streak: _newStreak,
                      onDone: () => Navigator.of(context).pop(),
                      onGoDeeper: _goDeeper,
                    ),
                },
              ),
            ),
          ),
          // XP burst overlay
          if (_showXpBurst)
            XpBurstOverlay(
              xp: _burstAmount,
              onComplete: () => setState(() => _showXpBurst = false),
            ),
        ],
      ),
    );
  }

  void _triggerBurst(int xp) {
    setState(() {
      _showXpBurst = true;
      _burstAmount = xp;
      _totalXpEarned += xp;
    });
  }

  void _onVerseRead() {
    _xpService.accumulateXp(widget.uid, XpRewards.readVerse);
    _triggerBurst(XpRewards.readVerse);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _step = _SparkStep.question);
    });
  }

  Future<void> _onAnswerSubmit() async {
    setState(() => _submitting = true);

    _xpService.accumulateXp(widget.uid, XpRewards.answerAiQuestion);
    _triggerBurst(XpRewards.answerAiQuestion);

    final streakResult = await _streakService.recordActivity(widget.uid);
    final xpResult = await _xpService.flushSession(widget.uid);

    HapticFeedback.heavyImpact();

    setState(() {
      _step = _SparkStep.celebration;
      _newStreak = streakResult.newStreak;
      _totalXpEarned = xpResult.xpEarned;
      _submitting = false;
    });
  }

  void _goDeeper() {
    // Navigate to full Bible Reader
    Navigator.of(context).pop();
  }
}

// ── Step 3a: Verse ────────────────────────────────────────────────────────────

class _VerseStep extends StatelessWidget {
  final SparkQuestion question;
  final VoidCallback onRead;

  const _VerseStep({required this.question, required this.onRead});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 40),
      child: Column(
        children: [
          const Spacer(),
          Text(
            question.reference,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.warmGold,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            '"${question.verseText}"',
            style: AppTypography.verseLarge,
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 2),
          FlameCTAButton(
            label: "I've read it  ✓",
            onPressed: onRead,
          ),
        ],
      ),
    );
  }
}

// ── Step 3b: Question ─────────────────────────────────────────────────────────

class _QuestionStep extends StatelessWidget {
  final String question;
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  const _QuestionStep({
    required this.question,
    required this.controller,
    required this.submitting,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 60, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(question, style: AppTypography.bodyLarge),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            maxLines: 4,
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Type anything that comes to mind…',
            ),
            autofocus: true,
          ),
          const Spacer(),
          FlameCTAButton(
            label: "That's my answer →",
            isLoading: submitting,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSkip,
              child: const Text('Skip', style: AppTypography.bodySmall),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3c: Celebration ──────────────────────────────────────────────────────

class _CelebrationStep extends StatefulWidget {
  final int xpEarned;
  final int streak;
  final VoidCallback onDone;
  final VoidCallback onGoDeeper;

  const _CelebrationStep({
    required this.xpEarned,
    required this.streak,
    required this.onDone,
    required this.onGoDeeper,
  });

  @override
  State<_CelebrationStep> createState() => _CelebrationStepState();
}

class _CelebrationStepState extends State<_CelebrationStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text('Quest complete! 🔥', style: AppTypography.displayMedium),
            const SizedBox(height: 32),
            StreakDisplay(streak: widget.streak, large: true),
            const SizedBox(height: 32),
            Text(
              '+${widget.xpEarned} XP',
              style: AppTypography.xpDisplay,
            ),
            const SizedBox(height: 48),
            FlameCTAButton(
              label: 'Done for today',
              onPressed: widget.onDone,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onGoDeeper,
              child: Text(
                'Go deeper →',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
