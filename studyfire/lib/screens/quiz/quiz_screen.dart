import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
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

  const QuizScreen({super.key, required this.uid, this.topicTag});

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

  void _finish() {
    final perfect = _score == _questions.length;
    final xp = XpRewards.completeQuiz + (perfect ? XpRewards.perfectScoreBonus : 0);
    _xpService.accumulateXp(widget.uid, xp);
    _streakService.recordActivity(widget.uid).catchError((_) {});
    // Track questionsAnswered
    FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'profile': {'questionsAnswered': FieldValue.increment(_score)}
    }, SetOptions(merge: true)).catchError((_) {});
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
              onDone: () => Navigator.pop(context),
              onPostToGroup: () {},
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
  final VoidCallback onDone;
  final VoidCallback onPostToGroup;

  const _QuizResultScreen({
    required this.score,
    required this.total,
    required this.xpEarned,
    required this.topicTag,
    required this.onDone,
    required this.onPostToGroup,
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
          const SizedBox(height: 40),
          FlameCTAButton(label: 'Done', onPressed: onDone),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onPostToGroup,
            child: const Text('Post a question to group'),
          ),
        ],
      ),
    );
  }
}

// ── Quiz Home Screen ───────────────────────────────────────────────────────────

class QuizHomeScreen extends ConsumerWidget {
  final String uid;
  const QuizHomeScreen({super.key, required this.uid});

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

  static const _mastery = {
    'Anxiety & Fear': 'Growing',
    'Identity': 'Strong',
    'Prayer': 'Exploring',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(title: const Text('Quiz')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Today's Quiz card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TODAY\'S QUIZ', style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
                const SizedBox(height: 8),
                const Text('Identity', style: AppTypography.displaySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('5 questions', style: AppTypography.bodySmall),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warmGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('⚡ ${XpRewards.completeQuiz} XP',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuizScreen(uid: uid, topicTag: 'Identity'),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/start_quiz_button.png',
                    width: double.infinity,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('My Topics', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: _topics.length,
            itemBuilder: (_, i) {
              final (tag, imagePath) = _topics[i];
              final mastery = _mastery[tag] ?? 'Exploring';
              final masteryColor = mastery == 'Strong'
                  ? AppColors.emerald
                  : mastery == 'Growing'
                      ? AppColors.warmGold
                      : AppColors.textSecondary;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizScreen(uid: uid, topicTag: tag),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Image.asset(imagePath, width: 64, height: 64, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text(tag, style: AppTypography.labelSmall, maxLines: 2, textAlign: TextAlign.center),
                      const SizedBox(height: 2),
                      Text(mastery, style: AppTypography.bodySmall.copyWith(color: masteryColor, fontSize: 11), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
