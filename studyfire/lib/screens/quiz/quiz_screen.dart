import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'blitz_screen.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/walkthrough/walkthrough_keys.dart';
import '../../core/services/streak_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/gamification/xp_burst.dart';

enum QuestionType { multipleChoice, trueFalse, fillBlank, passageMatching }

class QuizQuestion {
  final QuestionType type;
  final String question;
  final List<String>? options;
  final String correctAnswer;
  final String explanation;
  final String topicTag;
  final String? passageRef;

  const QuizQuestion({
    required this.type,
    required this.question,
    this.options,
    required this.correctAnswer,
    required this.explanation,
    required this.topicTag,
    this.passageRef,
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> m) => QuizQuestion(
        type: QuestionType.values.firstWhere(
          (e) => e.name == m['type'],
          orElse: () => QuestionType.multipleChoice,
        ),
        question: m['question'] ?? '',
        options: m['options'] != null ? List<String>.from(m['options']) : null,
        correctAnswer: m['correctAnswer'] ?? '',
        explanation: m['explanation'] ?? '',
        topicTag: m['topicTag'] ?? '',
        passageRef: m['passageRef'],
      );
}

class QuizScreen extends ConsumerStatefulWidget {
  final String uid;
  final String? topicTag; // null = today's assigned topic
  final bool isDailyQuiz;

  const QuizScreen({super.key, required this.uid, this.topicTag, this.isDailyQuiz = false});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  List<QuizQuestion> _questions = [];
  bool _loading = true;
  int _current = 0;
  String? _selectedAnswer;
  bool _answered = false;
  bool _correct = false;
  int _score = 0;
  int _totalXp = 0;
  bool _completed = false;
  bool _showXpBurst = false;
  int _burstXp = 0;

  // Tracks (question, userAnswer) for every wrong answer
  final List<({QuizQuestion question, String userAnswer})> _missed = [];

  final _xpService = XpService();
  final _streakService = StreakService();

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _loading = true);
    
    // Try loading from Firestore daily cache first
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final doc = await FirebaseFirestore.instance
          .collection('dailycache')
          .doc(today)
          .get();
      final quizData = doc.data()?['quizQuestions'] as Map?;
      if (quizData != null && widget.topicTag != null) {
        final topicQuestions = quizData[widget.topicTag] as List?;
        if (topicQuestions != null && topicQuestions.isNotEmpty) {
          final loaded = topicQuestions.map((q) {
            final map = q as Map;
            final typeStr = map['type'] as String? ?? 'multiple_choice';
            final type = typeStr == 'true_false' ? QuestionType.trueFalse
                : typeStr == 'fill_blank' ? QuestionType.fillBlank
                : typeStr == 'passage_matching' ? QuestionType.passageMatching
                : QuestionType.multipleChoice;
            return QuizQuestion(
              type: type,
              question: map['question'] as String? ?? '',
              options: (map['options'] as List?)?.map((o) => o.toString()).toList(),
              correctAnswer: map['correctAnswer'] as String? ?? '',
              explanation: map['explanation'] as String? ?? '',
              topicTag: map['topicTag'] as String? ?? widget.topicTag ?? '',
              passageRef: map['passageRef'] as String?,
            );
          }).toList();
          loaded.shuffle();
          _questions = loaded;
          setState(() => _loading = false);
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to load from Firestore: $e');
    }

    // Fall back to hardcoded questions
    final allQuestions = [
      const QuizQuestion(
        type: QuestionType.multipleChoice,
        question: 'In Romans 8:28, Paul says God works all things together for good for those who…',
        options: ['A. Follow all the rules', 'B. Love him and are called according to his purpose', 'C. Pray every day', 'D. Give generously'],
        correctAnswer: 'B. Love him and are called according to his purpose',
        explanation: 'Paul specifies two qualifiers: loving God AND being called according to his purpose — both matter.',
        topicTag: 'Identity',
        passageRef: 'Romans 8:28',
      ),
      const QuizQuestion(
        type: QuestionType.trueFalse,
        question: 'The word "agape" in the New Testament always refers to romantic love.',
        options: ['True', 'False'],
        correctAnswer: 'False',
        explanation: '"Agape" describes unconditional, self-giving love — not romantic love (which is "eros").',
        topicTag: 'Identity',
      ),
      const QuizQuestion(
        type: QuestionType.fillBlank,
        question: 'Complete the verse: "For I know the plans I have for you, declares the Lord, plans to ___ you and not to harm you." (Jeremiah 29:11)',
        correctAnswer: 'prosper',
        explanation: 'The Hebrew word "shalom" (peace/wholeness/prosperity) captures God\'s complete intent for his people.',
        topicTag: 'Purpose & Calling',
        passageRef: 'Jeremiah 29:11',
      ),
      const QuizQuestion(
        type: QuestionType.multipleChoice,
        question: 'Which of these best describes the Fruit of the Spirit from Galatians 5?',
        options: [
          'A. Love, joy, peace, patience, kindness, goodness, faithfulness, gentleness, self-control',
          'B. Faith, hope, charity',
          'C. Prayer, fasting, giving',
          'D. Baptism, communion, fellowship',
        ],
        correctAnswer: 'A. Love, joy, peace, patience, kindness, goodness, faithfulness, gentleness, self-control',
        explanation: 'These nine qualities are produced by the Holy Spirit\'s work in a believer\'s life — not earned by effort.',
        topicTag: 'The Holy Spirit',
        passageRef: 'Galatians 5:22-23',
      ),
      const QuizQuestion(
        type: QuestionType.passageMatching,
        question: 'Match: "Cast all your anxiety on him because he cares for you."',
        options: ['A. Matthew 6:33', 'B. 1 Peter 5:7', 'C. Philippians 4:6', 'D. Psalm 55:22'],
        correctAnswer: 'B. 1 Peter 5:7',
        explanation: 'Peter\'s letter encourages believers who are suffering to literally throw their worries onto God\'s care.',
        topicTag: 'Anxiety & Fear',
        passageRef: '1 Peter 5:7',
      ),
    ];
    // Filter by topic if specified
    var filtered = widget.topicTag != null
        ? allQuestions.where((q) => q.topicTag == widget.topicTag).toList()
        : allQuestions.toList();
    // If no questions for topic, show all
    if (filtered.isEmpty) filtered = allQuestions.toList();
    // Shuffle for variety
    filtered.shuffle();
    // Take only topic-specific questions (no cross-topic mixing)
    _questions = filtered;
    setState(() => _loading = false);
  }

  bool _isCorrect(String answer) {
    final q = _questions[_current];
    if (q.type == QuestionType.fillBlank) {
      return answer.toLowerCase().trim() == q.correctAnswer.toLowerCase().trim();
    }
    return _optionMatchesCorrect(answer, q.correctAnswer);
  }

  // Handles both full-text correctAnswer ("A. Full text") and letter-only ("A")
  // so existing Firestore cache still works after prompt format change.
  static bool _optionMatchesCorrect(String option, String correct) {
    if (option == correct) return true;
    if (RegExp(r'^[A-D]$').hasMatch(correct)) {
      return option.startsWith('$correct.');
    }
    return false;
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    final correct = _isCorrect(answer);
    HapticFeedback.mediumImpact();

    if (!correct) {
      _missed.add((question: _questions[_current], userAnswer: answer));
    }

    setState(() {
      _selectedAnswer = answer;
      _answered = true;
      _correct = correct;
      if (correct) _score++;
    });
  }

  void _next() {
    if (_current + 1 >= _questions.length) {
      _finish();
    } else {
      setState(() {
        _current++;
        _selectedAnswer = null;
        _answered = false;
        _correct = false;
      });
    }
  }

  void _skip() {
    if (_current + 1 >= _questions.length) {
      _finish();
    } else {
      setState(() {
        _current++;
        _selectedAnswer = null;
        _answered = false;
      });
    }
  }

  Future<void> _finish() async {
    final perfect = _score == _questions.length;
    final xp = XpRewards.completeQuiz + (perfect ? XpRewards.perfectScoreBonus : 0);
    _xpService.accumulateXp(widget.uid, xp);
    await _xpService.flushSession(widget.uid);
    _streakService.recordActivity(widget.uid).catchError((_) {});
    // Track questionsAnswered
    FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'profile': {'questionsAnswered': FieldValue.increment(_score)}
    }, SetOptions(merge: true)).catchError((_) {});
    // Persist daily quiz completion so the home card shows "done" state
    if (widget.isDailyQuiz) {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString('daily_quiz_done_$today', '$_score/${_questions.length}');
    }
    setState(() {
      _totalXp = xp;
      _burstXp = xp;
      _showXpBurst = true;
      _completed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('Quiz'),
        actions: [
          if (!_completed)
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
      body: Stack(
        children: [
          if (_completed)
            _QuizResultScreen(
              score: _score,
              total: _questions.length,
              xpEarned: _totalXp,
              topicTag: _questions.first.topicTag,
              missed: _missed,
              isDailyQuiz: widget.isDailyQuiz,
              onDone: () => Navigator.pop(context),
            )
          else
            _QuizQuestionView(
              question: _questions[_current],
              selectedAnswer: _selectedAnswer,
              answered: _answered,
              correct: _correct,
              onSelect: _selectAnswer,
              onNext: _next,
              onSkip: _skip,
            ),
          if (_showXpBurst)
            XpBurstOverlay(
              xp: _burstXp,
              onComplete: () => setState(() => _showXpBurst = false),
            ),
        ],
      ),
    );
  }
}

// ── Question View ─────────────────────────────────────────────────────────────

class _QuizQuestionView extends StatefulWidget {
  final QuizQuestion question;
  final String? selectedAnswer;
  final bool answered;
  final bool correct;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _QuizQuestionView({
    required this.question,
    required this.selectedAnswer,
    required this.answered,
    required this.correct,
    required this.onSelect,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<_QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends State<_QuizQuestionView> {
  final _fillCtrl = TextEditingController();

  @override
  void dispose() {
    _fillCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.indigoAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.question.topicTag,
              style: AppTypography.labelSmall.copyWith(color: AppColors.warmWhite),
            ),
          ),
          const SizedBox(height: 20),

          // Question
          Text(widget.question.question, style: AppTypography.bodyLarge),

          if (widget.question.passageRef != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.question.passageRef!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
            ),
          ],
          const SizedBox(height: 24),

          // Answer options
          if (widget.question.type == QuestionType.fillBlank) ...[
            if (!widget.answered) ...[
              TextField(
                controller: _fillCtrl,
                style: AppTypography.bodyLarge,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Type your answer…'),
              ),
              const SizedBox(height: 16),
              FlameCTAButton(
                label: 'Submit',
                onPressed: () => widget.onSelect(_fillCtrl.text.trim()),
              ),
            ] else
              _FeedbackBanner(correct: widget.correct, explanation: widget.question.explanation),
          ] else ...[
            ...?widget.question.options?.map((opt) => _AnswerOption(
                  label: opt,
                  selected: widget.selectedAnswer == opt,
                  answered: widget.answered,
                  correct: _QuizScreenState._optionMatchesCorrect(opt, widget.question.correctAnswer),
                  onTap: () => widget.onSelect(opt),
                )),
            if (widget.answered)
              _FeedbackBanner(
                correct: widget.correct,
                explanation: widget.question.explanation,
              ),
          ],

          if (widget.answered) ...[
            const SizedBox(height: 16),
            FlameCTAButton(
              label: 'Next →',
              onPressed: widget.onNext,
            ),
          ] else ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onSkip,
                child: const Text('Skip', style: AppTypography.bodySmall),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool answered;
  final bool correct;
  final VoidCallback onTap;

  const _AnswerOption({
    required this.label,
    required this.selected,
    required this.answered,
    required this.correct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color borderColor = AppColors.surface;
    Color bgColor = AppColors.surface;
    Color textColor = AppColors.warmWhite;

    if (answered) {
      if (correct) {
        borderColor = AppColors.emerald;
        bgColor = AppColors.emerald.withOpacity(0.15);
        textColor = AppColors.emerald;
      } else if (selected) {
        borderColor = AppColors.error;
        bgColor = AppColors.error.withOpacity(0.15);
        textColor = AppColors.error;
      }
    } else if (selected) {
      borderColor = AppColors.warmGold;
      bgColor = AppColors.warmGold.withOpacity(0.1);
    }

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTypography.bodyMedium.copyWith(color: textColor)),
            ),
            if (answered && correct)
              const Icon(Icons.check_circle, color: AppColors.emerald, size: 18),
            if (answered && selected && !correct)
              const Icon(Icons.cancel, color: AppColors.error, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  final bool correct;
  final String explanation;

  const _FeedbackBanner({required this.correct, required this.explanation});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: correct
            ? AppColors.emerald.withOpacity(0.1)
            : AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: correct
              ? AppColors.emerald.withOpacity(0.3)
              : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            correct ? '✓ ' : '✗ ',
            style: TextStyle(
              color: correct ? AppColors.emerald : AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(explanation, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ── Result Screen ─────────────────────────────────────────────────────────────

class _QuizResultScreen extends StatelessWidget {
  final int score;
  final int total;
  final int xpEarned;
  final String topicTag;
  final List<({QuizQuestion question, String userAnswer})> missed;
  final VoidCallback onDone;
  final bool isDailyQuiz;

  const _QuizResultScreen({
    required this.score,
    required this.total,
    required this.xpEarned,
    required this.topicTag,
    required this.missed,
    required this.onDone,
    this.isDailyQuiz = false,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (score / total * 100).round();
    final perfect = score == total;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            perfect ? '🎉' : score > total ~/ 2 ? '👍' : '💪',
            style: const TextStyle(fontSize: 56),
          ),
          const SizedBox(height: 16),
          Text(
            '$score / $total',
            style: AppTypography.displayLarge.copyWith(fontSize: 48),
          ),
          Text('$percentage% correct', style: AppTypography.bodyLarge),
          const SizedBox(height: 8),
          if (perfect)
            Text('Perfect score!', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
          const SizedBox(height: 24),
          // Topic gap analysis
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('📊 ', style: TextStyle(fontSize: 18)),
                Expanded(
                  child: Text(
                    score == total
                        ? 'Strong on $topicTag!'
                        : score >= total * 0.8
                            ? 'Good on $topicTag — a few gaps to revisit.'
                            : 'Some gaps in $topicTag. Worth digging deeper.',
                    style: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('+$xpEarned XP', style: AppTypography.xpDisplay),
          const SizedBox(height: 24),
          // Share score button
          if (isDailyQuiz)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  final blocks = List.generate(total, (i) => i < score ? '🟩' : '⬛').join('');
                  final date = DateFormat('MMMM d, y').format(DateTime.now());
                  final text = '📖 StudyFire Daily Quiz\n'
                      'Topic: $topicTag\n'
                      '$blocks ($score/$total)\n'
                      '$date\n'
                      'studyfire.app';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Score copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.share_rounded, color: AppColors.warmGold, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Share my score',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Review missed questions button
          if (missed.isNotEmpty)
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.cardDark,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => _MissedQuestionsSheet(missed: missed),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.replay_rounded, color: AppColors.error, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Review ${missed.length} missed question${missed.length == 1 ? '' : 's'}',
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.error, size: 18),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FlameCTAButton(label: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}

// ── Missed Questions Review Sheet ─────────────────────────────────────────────

class _MissedQuestionsSheet extends StatelessWidget {
  final List<({QuizQuestion question, String userAnswer})> missed;

  const _MissedQuestionsSheet({required this.missed});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.replay_rounded, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Missed Questions',
                  style: AppTypography.labelLarge.copyWith(color: AppColors.warmWhite),
                ),
                const Spacer(),
                Text(
                  '${missed.length} total',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: missed.length,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (_, i) {
                final entry = missed[i];
                final q = entry.question;
                return _MissedQuestionCard(
                  index: i + 1,
                  question: q,
                  userAnswer: entry.userAnswer,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MissedQuestionCard extends StatelessWidget {
  final int index;
  final QuizQuestion question;
  final String userAnswer;

  const _MissedQuestionCard({
    required this.index,
    required this.question,
    required this.userAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question number + text
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.error,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(question.question, style: AppTypography.bodyMedium),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Your answer (wrong)
        if (userAnswer.isNotEmpty) ...[
          _ReviewAnswerRow(
            label: 'Your answer',
            text: userAnswer,
            color: AppColors.error,
            icon: Icons.close_rounded,
          ),
          const SizedBox(height: 8),
        ],

        // Correct answer
        _ReviewAnswerRow(
          label: 'Correct answer',
          text: question.correctAnswer,
          color: AppColors.emerald,
          icon: Icons.check_rounded,
        ),
        const SizedBox(height: 10),

        // Explanation
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡 ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Text(
                  question.explanation,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Passage ref badge
        if (question.passageRef != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warmGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.warmGold.withOpacity(0.25)),
            ),
            child: Text(
              question.passageRef!,
              style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReviewAnswerRow extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final IconData icon;

  const _ReviewAnswerRow({
    required this.label,
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: AppTypography.bodySmall.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Quiz Home Screen ───────────────────────────────────────────────────────────

class QuizHomeScreen extends ConsumerStatefulWidget {
  final String uid;
  const QuizHomeScreen({super.key, required this.uid});

  @override
  ConsumerState<QuizHomeScreen> createState() => _QuizHomeScreenState();
}

class _QuizHomeScreenState extends ConsumerState<QuizHomeScreen> {
  static const _topics = [
    ('Anxiety & Fear', 'assets/images/topics/topic_anxiety_fear.png'),
    ('Identity', 'assets/images/topics/topic_identity.png'),
    ('Purpose & Calling', 'assets/images/topics/topic_purpose_calling.png'),
    ('Forgiveness', 'assets/images/topics/topic_forgiveness.png'),
    ('Prayer', 'assets/images/topics/topic_prayer.png'),
    ('Relationships', 'assets/images/topics/topic_relationships.png'),
    ('Doubt & Faith', 'assets/images/topics/topic_doubt_faith.png'),
    ('The Holy Spirit', 'assets/images/topics/topic_holy_spirit.png'),
    ('Suffering', 'assets/images/topics/topic_suffering.png'),
    ('Spiritual Growth', 'assets/images/topics/topic_spiritual_growth.png'),
  ];

  // Today's featured topic rotates daily through all 10 topics
  static String get _todaysTopic {
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return _topics[dayOfYear % _topics.length].$1;
  }

  // Map of topicTag → today's representative passageRef (from dailycache)
  Map<String, String> _topicVerses = {};
  int _todaysQuestionCount = 5;

  // Daily completion — null = not done, "score/total" = done
  String? _dailyDoneScore;

  // Countdown to midnight
  Timer? _countdownTimer;
  String _countdown = '';

  @override
  void initState() {
    super.initState();
    _loadDailyVerses();
    _loadDailyCompletion();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDailyCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final saved = prefs.getString('daily_quiz_done_$today');
    if (mounted) setState(() => _dailyDoneScore = saved);
  }

  void _startCountdown() {
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown();
    });
  }

  void _updateCountdown() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final diff = midnight.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    setState(() {
      _countdown =
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _loadDailyVerses() async {
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final doc = await FirebaseFirestore.instance
          .collection('dailycache')
          .doc(today)
          .get();
      final quizData = doc.data()?['quizQuestions'] as Map?;
      if (quizData == null) return;

      final verses = <String, String>{};
      for (final (tag, _) in _topics) {
        final questions = quizData[tag] as List?;
        if (questions != null && questions.isNotEmpty) {
          // Find first question with a passageRef
          for (final q in questions) {
            final ref = (q as Map)['passageRef'] as String?;
            if (ref != null && ref.isNotEmpty) {
              verses[tag] = ref;
              break;
            }
          }
          // Update today's question count for the featured topic
          if (tag == _todaysTopic) {
            _todaysQuestionCount = questions.length.clamp(1, 10);
          }
        }
      }
      if (mounted) setState(() => _topicVerses = verses);
    } catch (e) {
      debugPrint('QuizHome: failed to load daily verses: $e');
    }
  }

  void _shareScore(String scoreText, String topic) {
    final parts = scoreText.split('/');
    final score = int.tryParse(parts[0]) ?? 0;
    final total = int.tryParse(parts.length > 1 ? parts[1] : '5') ?? 5;
    final blocks = List.generate(total, (i) => i < score ? '🟩' : '⬛').join('');
    final date = DateFormat('MMMM d, y').format(DateTime.now());
    final text = '📖 StudyFire Daily Quiz\n'
        'Topic: $topic\n'
        '$blocks ($scoreText)\n'
        '$date\n'
        'studyfire.app';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Score copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todaysTopic = _todaysTopic;
    final isDone = _dailyDoneScore != null;

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(title: const Text('Quiz')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Today's Daily Quiz card ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDone
                  ? AppColors.emerald.withOpacity(0.08)
                  : AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDone
                    ? AppColors.emerald.withOpacity(0.4)
                    : AppColors.warmGold.withOpacity(0.3),
              ),
            ),
            child: isDone
                ? _buildCompletedCard(todaysTopic)
                : _buildStartCard(todaysTopic),
          ),
          const SizedBox(height: 16),

          // ── Lightning Trial card ─────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top section — label, title, subtitle, badge
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Text column — Expanded so it never overflows
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚡ LIGHTNING TRIAL',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.warmGold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'True / False Blitz',
                              style: AppTypography.labelLarge.copyWith(
                                color: AppColors.warmWhite,
                                fontSize: 20,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '5 sec/question · Combos · 4× XP',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Badge — fixed size, never grows
                      Image.asset(
                        'assets/images/badges/lightning.png',
                        width: 60,
                        height: 60,
                        errorBuilder: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.warmGold.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.warmGold.withOpacity(0.4)),
                          ),
                          child: const Icon(Icons.bolt_rounded,
                              color: AppColors.warmGold, size: 30),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Start Blitz button
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrueFalseBlitzScreen(uid: widget.uid),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.warmGold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warmGold.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bolt_rounded,
                            color: AppColors.warmGold, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Start Blitz',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.warmGold,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppColors.warmGold, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Practice by Topic ────────────────────────────────────────────
          Text('Practice by Topic', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              key: WalkthroughKeys.quizTopicGrid,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 4),
              itemCount: _topics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final (tag, imagePath) = _topics[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          QuizScreen(uid: widget.uid, topicTag: tag),
                    ),
                  ),
                  child: Container(
                    width: 78,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 62,
                          child: Image.asset(imagePath, fit: BoxFit.contain),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                          child: Text(
                            tag,
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 10,
                            ),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Completed card (shown after user finishes today's quiz) ────────────────

  Widget _buildCompletedCard(String topic) {
    final parts = _dailyDoneScore!.split('/');
    final score = int.tryParse(parts[0]) ?? 0;
    final total = int.tryParse(parts.length > 1 ? parts[1] : '5') ?? 5;
    final blocks = List.generate(total, (i) => i < score ? '🟩' : '⬛').join('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: COMPLETED badge + countdown
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'COMPLETED',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.emerald,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, color: AppColors.textSecondary, size: 12),
                const SizedBox(width: 4),
                Text(
                  'Next in $_countdown',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(topic, style: AppTypography.displaySmall),
        const SizedBox(height: 4),
        Text(
          'Score: $_dailyDoneScore',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(blocks, style: const TextStyle(fontSize: 22, letterSpacing: 2)),
        const SizedBox(height: 16),
        // Share button
        GestureDetector(
          onTap: () => _shareScore(_dailyDoneScore!, topic),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.warmGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.share_rounded, color: AppColors.warmGold, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Share my score',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Start card (shown before user takes today's quiz) ─────────────────────

  Widget _buildStartCard(String topic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TODAY\'S QUIZ',
          style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
        ),
        const SizedBox(height: 8),
        Text(topic, style: AppTypography.displaySmall),
        if (_topicVerses[topic] != null) ...[
          const SizedBox(height: 4),
          Text(
            _topicVerses[topic]!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text('$_todaysQuestionCount questions', style: AppTypography.bodySmall),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warmGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '⚡ ${XpRewards.completeQuiz} XP',
                style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuizScreen(
                  uid: widget.uid,
                  topicTag: topic,
                  isDailyQuiz: true,
                ),
              ),
            );
            // Refresh completion state when returning from quiz
            _loadDailyCompletion();
          },
          child: Image.asset(
            'assets/images/start_quiz_button.png',
            width: double.infinity,
            height: 80,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}
