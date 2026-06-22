import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/streak_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import 'quiz_screen.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kQuestionSeconds = 5;
const _kFeedbackMs = 600;
const _kMaxQuestions = 15;
const _kBaseXpPerCorrect = 5;

// Combo thresholds → multiplier
double _multiplierFor(int combo) {
  if (combo >= 10) return 4.0;
  if (combo >= 5) return 3.0;
  if (combo >= 3) return 2.0;
  return 1.0;
}

String _multiplierLabel(int combo) {
  if (combo >= 10) return '4×';
  if (combo >= 5) return '3×';
  if (combo >= 3) return '2×';
  return '1×';
}

// ── Hardcoded fallback questions ───────────────────────────────────────────────

const _kFallbackTF = [
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Jesus was born in Nazareth.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'Jesus was born in Bethlehem, not Nazareth — though he grew up there.',
    topicTag: 'Identity',
    passageRef: 'Luke 2:4-7',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'The word "agape" in the New Testament refers to romantic love.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: '"Agape" is unconditional, self-giving love. Romantic love in Greek is "eros."',
    topicTag: 'Identity',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Paul wrote the letter to the Romans while in prison.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'Romans was likely written from Corinth, not prison. Paul wrote letters like Ephesians from prison.',
    topicTag: 'Purpose & Calling',
    passageRef: 'Romans 16:23',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'The Fruit of the Spirit lists nine qualities.',
    options: ['True', 'False'],
    correctAnswer: 'True',
    explanation: 'Galatians 5:22-23 lists love, joy, peace, patience, kindness, goodness, faithfulness, gentleness, self-control — nine in total.',
    topicTag: 'The Holy Spirit',
    passageRef: 'Galatians 5:22-23',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Saul\'s name was changed to Paul after he met Jesus on the road to Damascus.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'The Bible never records a name change on that road. Paul simply used both names — Saul (Hebrew) and Paul (Roman/Greek). The name Paul appears later in Acts 13.',
    topicTag: 'Purpose & Calling',
    passageRef: 'Acts 9',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'The Lord\'s Prayer appears in the book of Psalms.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'The Lord\'s Prayer is found in Matthew 6:9-13 and Luke 11:2-4, taught by Jesus to his disciples.',
    topicTag: 'Prayer',
    passageRef: 'Matthew 6:9-13',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Lazarus was raised from the dead by Jesus after being in the tomb for four days.',
    options: ['True', 'False'],
    correctAnswer: 'True',
    explanation: 'John 11:39 confirms Lazarus had been in the tomb four days when Jesus commanded him to come out.',
    topicTag: 'Identity',
    passageRef: 'John 11:39',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Proverbs 3:5 says to trust in the Lord with all your heart and lean not on your own understanding.',
    options: ['True', 'False'],
    correctAnswer: 'True',
    explanation: 'Proverbs 3:5-6 is one of the most quoted passages: "Trust in the LORD with all your heart and lean not on your own understanding."',
    topicTag: 'Doubt & Faith',
    passageRef: 'Proverbs 3:5',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'The Holy Spirit descended like a dove at Jesus\' baptism.',
    options: ['True', 'False'],
    correctAnswer: 'True',
    explanation: 'All four Gospels record the Holy Spirit descending like a dove when Jesus was baptized by John.',
    topicTag: 'The Holy Spirit',
    passageRef: 'Matthew 3:16',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Job never questioned God during his suffering.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'Job openly questioned God throughout the book, even demanding an audience. God ultimately honored his honesty over his friends\' empty theology.',
    topicTag: 'Suffering',
    passageRef: 'Job 13:3',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: 'Forgiveness in the Bible is always conditioned on the other person apologizing first.',
    options: ['True', 'False'],
    correctAnswer: 'False',
    explanation: 'Jesus forgave people before they asked, and commanded believers to forgive "seventy times seven" — without waiting for an apology.',
    topicTag: 'Forgiveness',
    passageRef: 'Matthew 18:22',
  ),
  QuizQuestion(
    type: QuestionType.trueFalse,
    question: '"Be anxious for nothing" is a phrase from Philippians 4:6.',
    options: ['True', 'False'],
    correctAnswer: 'True',
    explanation: 'Philippians 4:6 (NKJV) says "Be anxious for nothing, but in everything by prayer and supplication... let your requests be made known to God."',
    topicTag: 'Anxiety & Fear',
    passageRef: 'Philippians 4:6',
  ),
];

// ── Main Blitz Screen ─────────────────────────────────────────────────────────

class TrueFalseBlitzScreen extends ConsumerStatefulWidget {
  final String uid;
  const TrueFalseBlitzScreen({super.key, required this.uid});

  @override
  ConsumerState<TrueFalseBlitzScreen> createState() =>
      _TrueFalseBlitzScreenState();
}

class _TrueFalseBlitzScreenState extends ConsumerState<TrueFalseBlitzScreen>
    with SingleTickerProviderStateMixin {
  // ── Data ────────────────────────────────────────────────────────────────────
  List<QuizQuestion> _questions = [];
  bool _loading = true;

  // ── Game state ──────────────────────────────────────────────────────────────
  int _current = 0;
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _totalXp = 0;
  bool _finished = false;
  bool _showFeedback = false;
  bool _lastCorrect = false;

  // ── Timer ────────────────────────────────────────────────────────────────────
  late final AnimationController _timerCtrl;
  Timer? _autoAdvanceTimer;

  final _xpService = XpService();
  final _streakService = StreakService();

  @override
  void initState() {
    super.initState();
    _timerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _kQuestionSeconds),
    );
    _loadQuestions();
  }

  @override
  void dispose() {
    _timerCtrl.dispose();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadQuestions() async {
    final allTf = <QuizQuestion>[];
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final doc = await FirebaseFirestore.instance
          .collection('dailycache')
          .doc(today)
          .get();
      final quizData = doc.data()?['quizQuestions'] as Map?;
      if (quizData != null) {
        for (final entry in quizData.entries) {
          final questions = entry.value as List?;
          if (questions == null) continue;
          for (final q in questions) {
            final map = q as Map;
            final typeStr = map['type'] as String? ?? '';
            if (typeStr == 'true_false') {
              allTf.add(QuizQuestion(
                type: QuestionType.trueFalse,
                question: map['question'] as String? ?? '',
                options: const ['True', 'False'],
                correctAnswer: map['correctAnswer'] as String? ?? '',
                explanation: map['explanation'] as String? ?? '',
                topicTag: map['topicTag'] as String? ?? '',
                passageRef: map['passageRef'] as String?,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Blitz: Firestore load failed: $e');
    }

    if (allTf.isEmpty) allTf.addAll(_kFallbackTF);
    allTf.shuffle();

    if (mounted) {
      setState(() {
        _questions = allTf.take(_kMaxQuestions).toList();
        _loading = false;
      });
      _startTimer();
    }
  }

  // ── Timer logic ───────────────────────────────────────────────────────────────

  void _startTimer() {
    _autoAdvanceTimer?.cancel();
    _timerCtrl.forward(from: 0).then((_) {
      // Animation completed = time ran out
      if (mounted && !_showFeedback && !_finished) {
        _resolveAnswer(null); // time's up
      }
    });
  }

  void _stopTimer() {
    _timerCtrl.stop();
    _autoAdvanceTimer?.cancel();
  }

  // ── Answer logic ──────────────────────────────────────────────────────────────

  void _onTap(String choice) {
    if (_showFeedback || _finished || _loading) return;
    _stopTimer();
    _resolveAnswer(choice);
  }

  void _resolveAnswer(String? choice) {
    final q = _questions[_current];

    // Normalize: compare lowercase to handle "True"/"False"/"true"/"false"
    final correct = choice != null &&
        choice.toLowerCase() == q.correctAnswer.toLowerCase();

    HapticFeedback.mediumImpact();

    final newCombo = correct ? _combo + 1 : 0;
    final multiplier = _multiplierFor(newCombo);
    final xpEarned = correct ? (_kBaseXpPerCorrect * multiplier).round() : 0;

    setState(() {
      _showFeedback = true;
      _lastCorrect = correct;
      if (correct) _score++;
      _combo = newCombo;
      if (_combo > _maxCombo) _maxCombo = _combo;
      _totalXp += xpEarned;
    });

    // Brief feedback, then advance
    _autoAdvanceTimer = Timer(const Duration(milliseconds: _kFeedbackMs), () {
      if (!mounted) return;
      if (_current + 1 >= _questions.length) {
        _finish();
      } else {
        setState(() {
          _current++;
          _showFeedback = false;
        });
        _startTimer();
      }
    });
  }

  Future<void> _finish() async {
    setState(() => _finished = true);
    if (_totalXp > 0) {
      _xpService.accumulateXp(widget.uid, _totalXp);
      await _xpService.flushSession(widget.uid);
    }
    _streakService.recordActivity(widget.uid).catchError((_) {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_finished) {
      return _BlitzResultScreen(
        score: _score,
        total: _questions.length,
        maxCombo: _maxCombo,
        xpEarned: _totalXp,
        onDone: () => Navigator.pop(context),
      );
    }

    final q = _questions[_current];
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('⚡ True/False Blitz'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_current + 1} / ${_questions.length}',
                style: AppTypography.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            // ── Stats row ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Correct count
                Text(
                  '✓ $_score',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.emerald,
                    fontSize: 18,
                  ),
                ),

                // Combo badge (only when on streak)
                if (_combo >= 3)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      key: ValueKey(_combo),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warmGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.warmGold.withOpacity(0.5)),
                      ),
                      child: Text(
                        '🔥 $_combo  ${_multiplierLabel(_combo)} XP',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.warmGold),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Total XP
                Text(
                  '+$_totalXp XP',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.warmGold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Countdown ring ───────────────────────────────────────────────
            AnimatedBuilder(
              animation: _timerCtrl,
              builder: (_, __) {
                final remaining =
                    (_kQuestionSeconds * (1 - _timerCtrl.value)).ceil();
                final t = _timerCtrl.value; // 0 = start, 1 = end
                final ringColor = t < 0.5
                    ? AppColors.emerald
                    : t < 0.75
                        ? Colors.orange
                        : AppColors.error;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: CircularProgressIndicator(
                        value: 1 - t,
                        strokeWidth: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(ringColor),
                      ),
                    ),
                    Text(
                      '$remaining',
                      style: AppTypography.displaySmall.copyWith(
                        color: ringColor,
                        fontSize: 26,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // ── Question card ────────────────────────────────────────────────
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Container(
                    key: ValueKey(_current),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 28),
                    decoration: BoxDecoration(
                      color: _showFeedback
                          ? (_lastCorrect
                              ? AppColors.emerald.withOpacity(0.10)
                              : AppColors.error.withOpacity(0.10))
                          : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _showFeedback
                            ? (_lastCorrect
                                ? AppColors.emerald.withOpacity(0.6)
                                : AppColors.error.withOpacity(0.6))
                            : Colors.white12,
                        width: _showFeedback ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Feedback label
                        if (_showFeedback) ...[
                          Text(
                            _lastCorrect ? '✓  Correct!' : '✗  Wrong',
                            style: AppTypography.labelLarge.copyWith(
                              color: _lastCorrect
                                  ? AppColors.emerald
                                  : AppColors.error,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Question text
                        Text(
                          q.question,
                          style: AppTypography.bodyLarge.copyWith(height: 1.55),
                          textAlign: TextAlign.center,
                        ),

                        // Passage ref (only during feedback)
                        if (_showFeedback && q.passageRef != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.warmGold.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              q.passageRef!,
                              style: AppTypography.labelSmall
                                  .copyWith(color: AppColors.warmGold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Multiplier hint ───────────────────────────────────────────────
            if (_combo > 0 && _combo < 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${3 - _combo} more in a row for 2× XP!',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_combo == 0 && _current > 0)
              const SizedBox(height: 30)
            else
              const SizedBox.shrink(),

            // ── TRUE / FALSE buttons ──────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _BlitzButton(
                    label: 'TRUE',
                    color: AppColors.emerald,
                    enabled: !_showFeedback,
                    onTap: () => _onTap('True'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _BlitzButton(
                    label: 'FALSE',
                    color: AppColors.error,
                    enabled: !_showFeedback,
                    onTap: () => _onTap('False'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Blitz Button ──────────────────────────────────────────────────────────────

class _BlitzButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _BlitzButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 72,
        decoration: BoxDecoration(
          color: color.withOpacity(enabled ? 0.15 : 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(enabled ? 0.6 : 0.2),
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: color.withOpacity(enabled ? 1.0 : 0.4),
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Result Screen ─────────────────────────────────────────────────────────────

class _BlitzResultScreen extends StatelessWidget {
  final int score;
  final int total;
  final int maxCombo;
  final int xpEarned;
  final VoidCallback onDone;

  const _BlitzResultScreen({
    required this.score,
    required this.total,
    required this.maxCombo,
    required this.xpEarned,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (score / total * 100).round() : 0;
    final emoji = pct >= 90
        ? '⚡'
        : pct >= 70
            ? '🔥'
            : pct >= 50
                ? '💪'
                : '📖';

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),

              Text(
                '$score / $total',
                style: AppTypography.displayLarge.copyWith(fontSize: 52),
              ),
              Text('$pct% correct', style: AppTypography.bodyLarge),

              const SizedBox(height: 8),

              if (maxCombo >= 3) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.warmGold.withOpacity(0.35)),
                  ),
                  child: Text(
                    '🔥 Best combo: $maxCombo',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.warmGold),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 20),
              Text('+$xpEarned XP', style: AppTypography.xpDisplay),
              const SizedBox(height: 32),

              FlameCTAButton(label: 'Done', onPressed: onDone),
            ],
          ),
        ),
      ),
    );
  }
}
