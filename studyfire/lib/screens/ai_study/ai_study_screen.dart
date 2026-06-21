import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/premium_gate.dart';
import '../../widgets/gamification/xp_burst.dart';
import '../../app.dart';

// Response shape from Cloud Function
class AiStudyData {
  final List<String> questions;
  final String contextBrief;
  final String tldr;
  final List<String> themes;
  final List<String> crossRefs;
  final String? characterSpotlight;
  final String devotionalPrompt;

  const AiStudyData({
    required this.questions,
    required this.contextBrief,
    required this.tldr,
    required this.themes,
    required this.crossRefs,
    this.characterSpotlight,
    required this.devotionalPrompt,
  });

  factory AiStudyData.fromMap(Map<String, dynamic> m) => AiStudyData(
        questions: List<String>.from(m['questions'] ?? []),
        contextBrief: m['contextBrief'] ?? '',
        tldr: m['tldr'] ?? '',
        themes: List<String>.from(m['themes'] ?? []),
        crossRefs: List<String>.from(m['crossRefs'] ?? []),
        characterSpotlight: m['characterSpotlight'],
        devotionalPrompt: m['devotionalPrompt'] ?? '',
      );
}

class AiStudyScreen extends ConsumerStatefulWidget {
  final String passage;
  final String reference;
  final String version;
  final String uid;
  final String? passageId;
  final AiStudyData? preloaded; // if called from cached Spark result

  const AiStudyScreen({
    super.key,
    required this.passage,
    required this.reference,
    required this.version,
    required this.uid,
    this.passageId,
    this.preloaded,
  });

  @override
  ConsumerState<AiStudyScreen> createState() => _AiStudyScreenState();
}

class _AiStudyScreenState extends ConsumerState<AiStudyScreen> {
  AiStudyData? _data;
  bool _loading = true;
  String? _error;
  int _currentQuestion = 0;
  final List<String> _answers = [];
  final _answerCtrl = TextEditingController();
  bool _showingFeedback = false;
  String? _aiFeedback;
  bool _submittingAnswer = false;
  int _totalXp = 0;
  bool _showXpBurst = false;
  int _burstXp = 0;
  bool _completed = false;
  bool _contextExpanded = false;
  bool _loadStarted = false;

  final _xpService = XpService();

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _data = widget.preloaded;
      _loading = false;
      _answers.addAll(List.filled(_data!.questions.length, ''));
    }
    // _loadStudy() is triggered lazily from build() only after isPremium is
    // confirmed — prevents a wasted Cloud Function call for free users who hit
    // the paywall before any data loads.
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudy() async {
    setState(() { _loading = true; _error = null; });
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getAiStudy', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      // Derive a stable cache key: use passageId if provided, else slug the reference
      final passageId = widget.passageId ??
          widget.reference.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

      // Read the user's study level from their Firestore profile
      final profileAsync = ref.read(currentProfileProvider);
      final studyLevel = profileAsync.valueOrNull?.studyLevel.name ?? 'beginner';

      final result = await fn.call({
        'passageId': passageId,
        'passageText': widget.passage,
        'reference': widget.reference,
        'version': widget.version,
        'studyLevel': studyLevel,
        'studyGoal': 'devotional',
        'topicTagMastery': <String, String>{},
        'recentQuizHistory': <String>[],
      });

      _data = AiStudyData.fromMap(Map<String, dynamic>.from(result.data as Map));
      _answers.addAll(List.filled(_data!.questions.length, ''));
      setState(() => _loading = false);
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'Could not load study. Try again.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load study. Try again.';
      });
    }
  }

  Future<void> _submitAnswer() async {
    if (_answerCtrl.text.trim().isEmpty) return;
    setState(() => _submittingAnswer = true);

    _answers[_currentQuestion] = _answerCtrl.text.trim();

    // Brief affirmation — in production: call Claude for per-answer feedback
    final affirmations = [
      'Nice observation! Sitting with that for a moment really matters.',
      'That\'s a thoughtful take. You\'re reading carefully.',
      'Good reflection — that kind of honest engagement is exactly what grows faith.',
      'Love that connection. Keep building on it.',
      'That\'s the kind of answer that sticks.',
    ];
    final feedback = affirmations[_currentQuestion % affirmations.length];

    _xpService.accumulateXp(widget.uid, XpRewards.answerAiQuestion);

    setState(() {
      _submittingAnswer = false;
      _aiFeedback = feedback;
      _showingFeedback = true;
      _burstXp = XpRewards.answerAiQuestion;
      _showXpBurst = true;
      _totalXp += XpRewards.answerAiQuestion;
    });

    HapticFeedback.mediumImpact();
  }

  void _nextQuestion() {
    _answerCtrl.clear();
    if (_currentQuestion + 1 >= (_data?.questions.length ?? 0)) {
      setState(() => _completed = true);
    } else {
      setState(() {
        _currentQuestion++;
        _showingFeedback = false;
        _aiFeedback = null;
      });
    }
  }

  static const _bookIds = {
    'Genesis': 'gen', 'Exodus': 'exo', 'Leviticus': 'lev', 'Numbers': 'num',
    'Deuteronomy': 'deu', 'Joshua': 'jos', 'Judges': 'jdg', 'Ruth': 'rut',
    '1 Samuel': '1sa', '2 Samuel': '2sa', '1 Kings': '1ki', '2 Kings': '2ki',
    '1 Chronicles': '1ch', '2 Chronicles': '2ch', 'Ezra': 'ezr', 'Nehemiah': 'neh',
    'Esther': 'est', 'Job': 'job', 'Psalms': 'psa', 'Psalm': 'psa', 'Proverbs': 'pro',
    'Ecclesiastes': 'ecc', 'Song of Solomon': 'sng', 'Isaiah': 'isa',
    'Jeremiah': 'jer', 'Lamentations': 'lam', 'Ezekiel': 'ezk', 'Daniel': 'dan',
    'Hosea': 'hos', 'Joel': 'jol', 'Amos': 'amo', 'Obadiah': 'oba',
    'Jonah': 'jon', 'Micah': 'mic', 'Nahum': 'nam', 'Habakkuk': 'hab',
    'Zephaniah': 'zep', 'Haggai': 'hag', 'Zechariah': 'zec', 'Malachi': 'mal',
    'Matthew': 'mat', 'Mark': 'mrk', 'Luke': 'luk', 'John': 'jhn',
    'Acts': 'act', 'Romans': 'rom', '1 Corinthians': '1co', '2 Corinthians': '2co',
    'Galatians': 'gal', 'Ephesians': 'eph', 'Philippians': 'php', 'Colossians': 'col',
    '1 Thessalonians': '1th', '2 Thessalonians': '2th', '1 Timothy': '1ti',
    '2 Timothy': '2ti', 'Titus': 'tit', 'Philemon': 'phm', 'Hebrews': 'heb',
    'James': 'jas', '1 Peter': '1pe', '2 Peter': '2pe', '1 John': '1jn',
    '2 John': '2jn', '3 John': '3jn', 'Jude': 'jud', 'Revelation': 'rev',
  };

  void _openCrossReference(String ref) {
    // Parse "Book Chapter:Verse" or "Book Chapter"
    final match = RegExp(r'^(.+?)\s+(\d+)(?::(\d+))?$').firstMatch(ref.trim());
    if (match == null) return;

    final bookName = match.group(1)!;
    final chapter = int.tryParse(match.group(2) ?? '1') ?? 1;
    final verse = int.tryParse(match.group(3) ?? '1') ?? 1;
    final bookId = _bookIds[bookName] ?? bookName.toLowerCase().replaceAll(' ', '_');

    context.push('/reader', extra: {
      'book': bookId,
      'chapter': chapter,
      'startVerse': verse,
      'version': widget.version,
    });
  }

  void _skipQuestion() {
    _answers[_currentQuestion] = '';
    _answerCtrl.clear();
    if (_currentQuestion + 1 >= (_data?.questions.length ?? 0)) {
      setState(() => _completed = true);
    } else {
      setState(() {
        _currentQuestion++;
        _showingFeedback = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Premium gate — read profile from Riverpod (already available app-wide)
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isPremium = profile?.isPremium ?? false;
    if (!isPremium) {
      return _AiStudyPaywall(onBack: () => Navigator.maybePop(context));
    }

    // Trigger load now that we've confirmed premium — only fires once.
    if (_loading && !_loadStarted && widget.preloaded == null) {
      _loadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadStudy();
      });
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: AppTypography.bodyLarge),
              const SizedBox(height: 16),
              FlameCTAButton(label: 'Retry', onPressed: _loadStudy),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(widget.reference, style: AppTypography.labelMedium),
        actions: [
          if (!_completed)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Q ${_currentQuestion + 1} of ${_data!.questions.length}',
                  style: AppTypography.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _completed ? _CompletionView(
            xpEarned: _totalXp,
            onDone: () => Navigator.pop(context),
          ) : _StudyView(
            data: _data!,
            currentQuestion: _currentQuestion,
            showingFeedback: _showingFeedback,
            aiFeedback: _aiFeedback,
            answerCtrl: _answerCtrl,
            submitting: _submittingAnswer,
            contextExpanded: _contextExpanded,
            onToggleContext: () => setState(() => _contextExpanded = !_contextExpanded),
            onSubmit: _submitAnswer,
            onSkip: _skipQuestion,
            onNext: _nextQuestion,
            onScriptureChipTap: (ref) => _openCrossReference(ref),
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

class _StudyView extends StatelessWidget {
  final AiStudyData data;
  final int currentQuestion;
  final bool showingFeedback;
  final String? aiFeedback;
  final TextEditingController answerCtrl;
  final bool submitting;
  final bool contextExpanded;
  final VoidCallback onToggleContext;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final ValueChanged<String> onScriptureChipTap;

  const _StudyView({
    required this.data,
    required this.currentQuestion,
    required this.showingFeedback,
    this.aiFeedback,
    required this.answerCtrl,
    required this.submitting,
    required this.contextExpanded,
    required this.onToggleContext,
    required this.onSubmit,
    required this.onSkip,
    required this.onNext,
    required this.onScriptureChipTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress dots
          Row(
            children: List.generate(data.questions.length, (i) => Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < currentQuestion
                    ? AppColors.emerald
                    : i == currentQuestion
                        ? AppColors.warmGold
                        : AppColors.surface,
              ),
            )),
          ),
          const SizedBox(height: 24),

          // Question
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(currentQuestion),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                data.questions[currentQuestion],
                style: AppTypography.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (!showingFeedback) ...[
            // Answer input
            TextField(
              controller: answerCtrl,
              maxLines: 4,
              style: AppTypography.bodyLarge,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type anything that comes to mind…',
              ),
            ),
            const SizedBox(height: 16),
            FlameCTAButton(
              label: 'Submit answer →',
              isLoading: submitting,
              onPressed: onSubmit,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                child: const Text('Skip this one →', style: AppTypography.bodySmall),
              ),
            ),
          ] else ...[
            // AI feedback
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
              ),
              child: Text(aiFeedback ?? '', style: AppTypography.bodyMedium),
            ),
            const SizedBox(height: 16),
            FlameCTAButton(label: 'Next question →', onPressed: onNext),
          ],

          const SizedBox(height: 28),

          // Content cards
          _ContentCard(
            title: 'Context',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contextExpanded ? data.contextBrief : data.tldr,
                  style: AppTypography.bodyMedium,
                ),
                TextButton(
                  onPressed: onToggleContext,
                  child: Text(
                    contextExpanded ? 'Show less' : 'Show more',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ContentCard(
            title: 'Themes',
            child: Wrap(
              spacing: 8,
              children: data.themes.map((t) => Chip(
                label: Text(t),
                backgroundColor: AppColors.indigoAccent.withOpacity(0.2),
                labelStyle: AppTypography.labelSmall.copyWith(color: AppColors.warmWhite),
                side: BorderSide(color: AppColors.indigoAccent.withOpacity(0.4)),
              )).toList(),
            ),
          ),
          const SizedBox(height: 12),

          _ContentCard(
            title: 'Cross-References',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.crossRefs.map((ref) => _ScriptureChip(
                ref: ref,
                onTap: () => onScriptureChipTap(ref),
              )).toList(),
            ),
          ),
          const SizedBox(height: 12),

          if (data.characterSpotlight != null)
            _ContentCard(
              title: 'Character Spotlight',
              child: Text(data.characterSpotlight!, style: AppTypography.bodyMedium),
            ),

          if (data.characterSpotlight != null) const SizedBox(height: 12),

          _ContentCard(
            title: 'Reflect',
            child: Text(data.devotionalPrompt, style: AppTypography.bodyMedium.copyWith(
              fontStyle: FontStyle.italic,
            )),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ContentCard extends StatefulWidget {
  final String title;
  final Widget child;

  const _ContentCard({required this.title, required this.child});

  @override
  State<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<_ContentCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(widget.title, style: AppTypography.labelMedium),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _ScriptureChip extends StatelessWidget {
  final String ref;
  final VoidCallback onTap;

  const _ScriptureChip({required this.ref, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.warmGold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
        ),
        child: Text(
          ref,
          style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
        ),
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  final int xpEarned;
  final VoidCallback onDone;

  const _CompletionView({
    required this.xpEarned,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('You finished today\'s study! 🔥', style: AppTypography.displaySmall),
          const SizedBox(height: 24),
          Text('+$xpEarned XP', style: AppTypography.xpDisplay),
          const SizedBox(height: 48),
          FlameCTAButton(label: 'Done', onPressed: onDone),
        ],
      ),
    );
  }
}

// ── Premium paywall for AI Study Screen ──────────────────────────────────────

class _AiStudyPaywall extends StatelessWidget {
  final VoidCallback onBack;
  const _AiStudyPaywall({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        backgroundColor: AppColors.deepSlate,
        leading: BackButton(onPressed: onBack),
        title: const Text('AI Study Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🤖', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 24),
            const Text('AI Study Mode', style: AppTypography.displaySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Get AI-generated study questions, historical context, cross-references, and a personal devotional prompt for any passage.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '\$3.99/month · \$29.99/year · \$19.99 student',
              style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FlameCTAButton(
              label: 'Unlock Premium — \$3.99/mo',
              onPressed: () {
                // TODO: RevenueCat.presentPaywall()
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: Text('Not now', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
