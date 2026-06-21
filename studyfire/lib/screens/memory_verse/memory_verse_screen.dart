import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/xp_service.dart';
import '../../core/services/group_activity_service.dart';
import '../../models/group.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../models/memory_verse.dart';
import '../../core/services/firestore_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/gamification/xp_burst.dart';

class MemoryVerseScreen extends ConsumerStatefulWidget {
  final MemoryVerse verse;
  final String uid;
  final bool isReview;

  const MemoryVerseScreen({
    super.key,
    required this.verse,
    required this.uid,
    this.isReview = false,
  });

  @override
  ConsumerState<MemoryVerseScreen> createState() => _MemoryVerseScreenState();
}

class _MemoryVerseScreenState extends ConsumerState<MemoryVerseScreen> {
  late MemoryVerseStage _currentStage;
  int _totalXp = 0;
  bool _showXpBurst = false;
  int _burstXp = 0;
  bool _stagePassed = false;

  @override
  void initState() {
    super.initState();
    _currentStage = widget.isReview
        ? MemoryVerseStage.stage5
        : widget.verse.currentStage;
  }

  void _awardXp(int xp) {
    setState(() {
      _burstXp = xp;
      _showXpBurst = true;
      _totalXp += xp;
    });
  }

  void _advanceStage() {
    if (_currentStage == MemoryVerseStage.stage5) {
      _onVersemastered();
      return;
    }
    final nextStage = MemoryVerseStage.values[_currentStage.index + 1];
    setState(() {
      _currentStage = nextStage;
      _stagePassed = false;
    });
    // Save progress (only if not mastered yet)
    if (nextStage != MemoryVerseStage.stage5) {
      FirestoreService().saveMemoryVerse(widget.uid, widget.verse.copyWith(currentStage: nextStage));
    }
  }

  Future<void> _onVersemastered() async {
    final db = FirestoreService();
    final now = DateTime.now();
    final reviewed = widget.verse.copyWith(
      mastered: true,
      currentStage: MemoryVerseStage.stage5,
      lastReviewed: now,
      nextReviewDate: _sm2NextDate(widget.verse.interval),
    );
    try {
      await db.saveMemoryVerse(widget.uid, reviewed);
      debugPrint('Saved mastered verse: \${widget.uid} \${reviewed.id} mastered=\${reviewed.mastered}');
    } catch (e) {
      debugPrint('Error saving mastered verse: \$e');
    }

    // Award XP
    final xpService = XpService();
    xpService.accumulateXp(widget.uid, XpRewards.memoryVerseMastered);
    await xpService.flushSession(widget.uid);

    // Post to group feed (onMemoryVerseMastered Cloud Function also fires)
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email?.split('@')[0] ?? 'Member';
    GroupActivityService().postActivityToUserGroups(
      widget.uid, name, FeedItemType.memoryVerseMastered,
      {'text': name + ' mastered ' + widget.verse.reference + ' 📖'},
    ).catchError((_) {});

    if (mounted) _showMasteredSheet();
  }

  DateTime _sm2NextDate(int interval) {
    return DateTime.now().add(Duration(days: interval.clamp(1, 365)));
  }

  void _showMasteredSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MasteredSheet(
        verse: widget.verse,
        xpEarned: _totalXp,
        onDone: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(
          'Stage ${_currentStage.index + 1} of 5',
          style: AppTypography.labelMedium,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(_currentStage),
                child: switch (_currentStage) {
                  MemoryVerseStage.stage1 => _Stage1ReadIt(
                      verse: widget.verse,
                      onComplete: () {
                        _awardXp(XpRewards.memoryStage1);
                        _advanceStage();
                      },
                    ),
                  MemoryVerseStage.stage2 => _Stage2FillGaps(
                      verse: widget.verse,
                      onComplete: (bonus) {
                        _awardXp(XpRewards.memoryStage2 + (bonus ? XpRewards.memoryStage2Bonus : 0));
                        _advanceStage();
                      },
                    ),
                  MemoryVerseStage.stage3 => _Stage3HalfGone(
                      verse: widget.verse,
                      onComplete: (bonus) {
                        _awardXp(XpRewards.memoryStage3 + (bonus ? XpRewards.memoryStage3Bonus : 0));
                        _advanceStage();
                      },
                    ),
                  MemoryVerseStage.stage4 => _Stage4AlmostThere(
                      verse: widget.verse,
                      onComplete: (bonus) {
                        _awardXp(XpRewards.memoryStage4 + (bonus ? XpRewards.memoryStage4Bonus : 0));
                        _advanceStage();
                      },
                    ),
                  MemoryVerseStage.stage5 => _Stage5WriteIt(
                      verse: widget.verse,
                      onComplete: (score, bonus) {
                        _awardXp(XpRewards.memoryStage5 + (bonus ? XpRewards.memoryStage5PerfectBonus : 0));
                        _advanceStage();
                      },
                    ),
                },
              ),
            ),
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

// ── Stage 1: Read It ──────────────────────────────────────────────────────────

class _Stage1ReadIt extends StatefulWidget {
  final MemoryVerse verse;
  final VoidCallback onComplete;

  const _Stage1ReadIt({required this.verse, required this.onComplete});

  @override
  State<_Stage1ReadIt> createState() => _Stage1ReadItState();
}

class _Stage1ReadItState extends State<_Stage1ReadIt> {
  int _readCount = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Tap the verse each time you read it',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (i) => GestureDetector(
                onTap: _readCount < 3 ? () => setState(() {
                  _readCount++;
                  HapticFeedback.lightImpact();
                }) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    i < _readCount ? Icons.circle : Icons.circle_outlined,
                    color: i < _readCount ? AppColors.warmGold : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            widget.verse.reference,
            style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _readCount < 3
                ? () => setState(() {
                      _readCount++;
                      HapticFeedback.lightImpact();
                    })
                : null,
            child: Text(
              '"${widget.verse.text}"',
              style: AppTypography.verseText,
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          AnimatedOpacity(
            opacity: _readCount >= 3 ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 300),
            child: FlameCTAButton(
              label: "I've got it  ✓  +${XpRewards.memoryStage1} XP",
              onPressed: _readCount >= 3 ? widget.onComplete : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stage 2: Fill the Gaps ────────────────────────────────────────────────────

class _Stage2FillGaps extends StatefulWidget {
  final MemoryVerse verse;
  final ValueChanged<bool> onComplete;

  const _Stage2FillGaps({required this.verse, required this.onComplete});

  @override
  State<_Stage2FillGaps> createState() => _Stage2FillGapsState();
}

class _Stage2FillGapsState extends State<_Stage2FillGaps> {
  late final List<String> _words;
  late final List<bool> _hidden;
  late final List<bool> _revealed;
  final _stopwatch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _words = widget.verse.text.split(' ');
    _hidden = List.generate(_words.length, (i) => (i + 1) % 4 == 0);
    _revealed = List.filled(_words.length, false);
  }

  bool get _allRevealed => !_hidden.asMap().entries
      .any((e) => e.value && !_revealed[e.key]);

  void _reveal(int idx) {
    setState(() => _revealed[idx] = true);
    HapticFeedback.selectionClick();
    if (_allRevealed) {
      final bonus = _stopwatch.elapsed.inSeconds < 30;
      widget.onComplete(bonus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Tap each hidden word to reveal it',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            widget.verse.reference,
            style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _words.asMap().entries.map((entry) {
              final i = entry.key;
              final word = entry.value;
              if (!_hidden[i]) {
                return Text(word, style: AppTypography.verseText);
              }
              if (_revealed[i]) {
                return Text(word,
                    style: AppTypography.verseText.copyWith(color: AppColors.warmGold));
              }
              return GestureDetector(
                onTap: () => _reveal(i),
                child: Container(
                  width: word.length * 9.0 + 12,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.indigoAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ── Stage 3: Half Gone ────────────────────────────────────────────────────────

class _Stage3HalfGone extends StatefulWidget {
  final MemoryVerse verse;
  final ValueChanged<bool> onComplete;

  const _Stage3HalfGone({required this.verse, required this.onComplete});

  @override
  State<_Stage3HalfGone> createState() => _Stage3HalfGoneState();
}

class _Stage3HalfGoneState extends State<_Stage3HalfGone> {
  late final List<String> _words;
  late final List<bool> _hidden;
  late final List<TextEditingController> _controllers;
  final Map<int, bool?> _results = {};
  bool _checked = false;
  int _errors = 0;

  @override
  void initState() {
    super.initState();
    _words = widget.verse.text.split(' ');
    _hidden = List.generate(_words.length, (i) => i % 2 == 1);
    _controllers = List.generate(
      _words.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  bool _fuzzyMatch(String answer, String expected) {
    final a = answer.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');
    final e = expected.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');
    if (a == e) return true;
    // Allow up to 2 character edits
    return _levenshtein(a, e) <= 2;
  }

  int _levenshtein(String a, String b) {
    final dp = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : j == 0 ? i : 0),
    );
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[a.length][b.length];
  }

  void _submit() {
    int errors = 0;
    for (int i = 0; i < _words.length; i++) {
      if (_hidden[i]) {
        final correct = _fuzzyMatch(_controllers[i].text, _words[i]);
        _results[i] = correct;
        if (!correct) errors++;
        if (!correct) HapticFeedback.heavyImpact();
      }
    }
    setState(() {
      _checked = true;
      _errors = errors;
    });

    if (errors == 0) {
      Future.delayed(const Duration(milliseconds: 600), () {
        widget.onComplete(true);
      });
    }
  }

  void _retry() => setState(() {
        _checked = false;
        _results.clear();
        for (final c in _controllers) c.clear();
      });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        children: [
          Text(
            widget.verse.reference,
            style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: _words.asMap().entries.map((entry) {
              final i = entry.key;
              final word = entry.value;
              if (!_hidden[i]) {
                return Text(word, style: AppTypography.verseText);
              }
              final result = _results[i];
              return SizedBox(
                width: (word.length * 11.0).clamp(48.0, 120.0),
                child: TextField(
                  controller: _controllers[i],
                  enabled: !_checked || result == false,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: result == null
                        ? AppColors.warmWhite
                        : result
                            ? AppColors.emerald
                            : AppColors.error,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: result == null
                        ? AppColors.surface
                        : result
                            ? AppColors.emerald.withOpacity(0.15)
                            : AppColors.error.withOpacity(0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          if (_checked && _errors > 0) ...[
            Text(
              '$_errors word${_errors == 1 ? '' : 's'} missed. Try again!',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FlameCTAButton(label: 'Try Again', onPressed: _retry),
          ] else if (!_checked) ...[
            FlameCTAButton(label: 'Check my answers', onPressed: _submit),
          ],
        ],
      ),
    );
  }
}

// ── Stage 4: Almost There ─────────────────────────────────────────────────────

class _Stage4AlmostThere extends StatefulWidget {
  final MemoryVerse verse;
  final ValueChanged<bool> onComplete;

  const _Stage4AlmostThere({required this.verse, required this.onComplete});

  @override
  State<_Stage4AlmostThere> createState() => _Stage4AlmostThereState();
}

class _Stage4AlmostThereState extends State<_Stage4AlmostThere> {
  late final List<String> _words;
  late final List<TextEditingController> _controllers;
  final Map<int, bool?> _results = {};
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _words = widget.verse.text.split(' ');
    _controllers = List.generate(_words.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  String _hint(String word) {
    if (word.isEmpty) return '';
    return '${word[0]}${'_' * (word.length - 1)}';
  }

  bool _fuzzyMatch(String a, String b) {
    final clean = (String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');
    final ca = clean(a);
    final cb = clean(b);
    if (ca == cb) return true;
    int diff = 0;
    final minLen = ca.length < cb.length ? ca.length : cb.length;
    for (int i = 0; i < minLen; i++) {
      if (ca[i] != cb[i]) diff++;
    }
    diff += (ca.length - cb.length).abs();
    return diff <= 2;
  }

  void _submit() {
    final results = <int, bool>{};
    for (int i = 0; i < _words.length; i++) {
      results[i] = _fuzzyMatch(_controllers[i].text, _words[i]);
    }
    final errors = results.values.where((v) => !v).length;
    setState(() {
      _results.addAll(results);
      _checked = true;
    });
    if (errors == 0) {
      Future.delayed(const Duration(milliseconds: 500), () => widget.onComplete(true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        children: [
          Text(
            widget.verse.reference,
            style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 8),
          Text(
            'First letter only — fill in the rest',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 20),
          ..._words.asMap().entries.map((entry) {
            final i = entry.key;
            final word = entry.value;
            final result = _results[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(
                    '${_hint(word)} ',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controllers[i],
                      style: AppTypography.bodyMedium.copyWith(
                        color: result == null
                            ? AppColors.warmWhite
                            : result
                                ? AppColors.emerald
                                : AppColors.error,
                      ),
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          if (!_checked)
            FlameCTAButton(label: 'Check', onPressed: _submit)
          else if (_results.values.any((v) => v == false)) ...[
            Text(
              '${_results.values.where((v) => v == false).length} word${_results.values.where((v) => v == false).length == 1 ? '' : 's'} missed. Try again!',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FlameCTAButton(
              label: 'Try Again',
              onPressed: () => setState(() {
                _checked = false;
                _results.clear();
                for (final c in _controllers) c.clear();
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stage 5: Write It ─────────────────────────────────────────────────────────

class _Stage5WriteIt extends StatefulWidget {
  final MemoryVerse verse;
  final void Function(double score, bool perfect) onComplete;

  const _Stage5WriteIt({required this.verse, required this.onComplete});

  @override
  State<_Stage5WriteIt> createState() => _Stage5WriteItState();
}

class _Stage5WriteItState extends State<_Stage5WriteIt> {
  final _ctrl = TextEditingController();
  List<_WordResult>? _results;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int _levenshtein(String a, String b) {
    final dp = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => i == 0 ? j : j == 0 ? i : 0),
    );
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[a.length][b.length];
  }

  _WordResult _score(String attempt, String expected) {
    final clean = (String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');
    final a = clean(attempt);
    final e = clean(expected);
    if (a == e) return _WordResult.correct;
    if (_levenshtein(a, e) <= 2) return _WordResult.close;
    return _WordResult.wrong;
  }

  void _submit() {
    final attempted = _ctrl.text.split(RegExp(r'\s+'));
    final expected = widget.verse.text.split(' ');
    final maxLen = attempted.length > expected.length ? attempted.length : expected.length;

    final results = List.generate(maxLen, (i) {
      if (i >= attempted.length) return _WordResult.wrong;
      if (i >= expected.length) return _WordResult.wrong;
      return _score(attempted[i], expected[i]);
    });

    final correctCount = results.where((r) => r != _WordResult.wrong).length;
    final score = correctCount / expected.length;
    final perfect = results.every((r) => r == _WordResult.correct);

    setState(() => _results = results);

    if (score >= 0.9) {
      Future.delayed(const Duration(milliseconds: 800), () {
        widget.onComplete(score, perfect);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.verse.reference,
            style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 8),
          Text(
            'Write the full verse from memory',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 24),
          if (_results == null) ...[
            TextField(
              controller: _ctrl,
              maxLines: 6,
              style: AppTypography.verseText,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type the verse…',
              ),
            ),
            const SizedBox(height: 20),
            FlameCTAButton(label: 'Submit', onPressed: _submit),
          ] else ...[
            _buildScoredText(),
            const SizedBox(height: 16),
            _buildLegend(),
            if (_results!.any((r) => r == _WordResult.wrong)) ...[
              const SizedBox(height: 20),
              Text(
                'Need 90% to pass. Keep going!',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FlameCTAButton(
                label: 'Try Again',
                onPressed: () => setState(() {
                  _results = null;
                  _ctrl.clear();
                }),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildScoredText() {
    final words = widget.verse.text.split(' ');
    return Wrap(
      spacing: 4,
      runSpacing: 8,
      children: _results!.asMap().entries.map((e) {
        final i = e.key;
        final result = e.value;
        final word = i < words.length ? words[i] : '?';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: switch (result) {
              _WordResult.correct => AppColors.emerald.withOpacity(0.2),
              _WordResult.close => AppColors.warmGold.withOpacity(0.2),
              _WordResult.wrong => AppColors.error.withOpacity(0.2),
            },
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            word,
            style: AppTypography.bodyMedium.copyWith(
              color: switch (result) {
                _WordResult.correct => AppColors.emerald,
                _WordResult.close => AppColors.warmGold,
                _WordResult.wrong => AppColors.error,
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegend() {
    return Row(
      children: [
        _LegendDot(color: AppColors.emerald, label: 'Correct'),
        const SizedBox(width: 16),
        _LegendDot(color: AppColors.warmGold, label: 'Close'),
        const SizedBox(width: 16),
        _LegendDot(color: AppColors.error, label: 'Wrong'),
      ],
    );
  }
}

enum _WordResult { correct, close, wrong }

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.bodySmall),
      ],
    );
  }
}

// ── Mastered Sheet ─────────────────────────────────────────────────────────────

class _MasteredSheet extends StatelessWidget {
  final MemoryVerse verse;
  final int xpEarned;
  final VoidCallback onDone;

  const _MasteredSheet({required this.verse, required this.xpEarned, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text('Verse Mastered!', style: AppTypography.displayMedium),
          const SizedBox(height: 8),
          Text(
            verse.reference,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
          ),
          const SizedBox(height: 16),
          Text(
            '+$xpEarned XP',
            style: AppTypography.xpDisplay,
          ),
          const SizedBox(height: 8),
          Text(
            'Added to Vault ✓',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.emerald),
          ),
          const SizedBox(height: 24),
          FlameCTAButton(label: 'Done', onPressed: onDone),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
