import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/session_length.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/walkthrough/walkthrough_keys.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/progress_bar.dart';
import '../../widgets/gamification/xp_burst.dart';
import 'package:go_router/go_router.dart';
import '../../app.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'spark_session_screen.dart';

class QuestScreen extends ConsumerStatefulWidget {
  const QuestScreen({super.key});

  @override
  ConsumerState<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends ConsumerState<QuestScreen> {
  SessionLength _sessionLength = SessionLength.spark;
  String _passage = 'Romans 8:28';
  bool _showSparkHint = false;
  StreamSubscription? _profileSub;
  String _passageId = 'rom_8_28';
  int _streak = 0;
  int _dailyXp = 0;
  int _totalXp = 0;
  String _studyLevel = 'Beginner';

  /// Daily XP goal scales with level: (next threshold − current threshold) ÷ 30,
  /// clamped to [50, 300]. Seeker→Disciple gap is 500 → goal 50 (min).
  int get _dailyXpGoal {
    final currentLevel = LevelThresholds.forXp(_totalXp);
    final currentFloor = currentLevel['xp'] as int;
    final nextThreshold = LevelThresholds.nextThreshold(_totalXp);
    if (nextThreshold == null) return 300; // max level
    final gap = nextThreshold - currentFloor;
    return (gap / 30).round().clamp(50, 300);
  }

  @override
  void initState() {
    super.initState();
    _loadTodaysPassage();
    _loadUserStats();
    _checkSparkHint();
  }

  Future<void> _checkSparkHint() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('hint_spark_session') ?? false;
    if (!seen && mounted) setState(() => _showSparkHint = true);
  }

  Future<void> _loadTodaysPassage() async {
    final today = DateTime.now().toIso8601String().split('T')[0];

    // Read manifest to find today's passageId
    final manifest = await FirebaseFirestore.instance
        .collection('sparkcache')
        .doc(today)
        .get();

    if (manifest.exists) {
      final data = manifest.data()!;
      final pid = data['passageId'] as String?;
      final reference = data['reference'] as String?;
      if (pid != null && reference != null && mounted) {
        setState(() {
          _passageId = pid;
          _passage = reference;
        });
        return;
      }
    }

    // Fallback: check a handful of known passage IDs if manifest missing
    final knownPassages = ['rom_8_28', 'jhn_3_16', 'psa_23_1', 'jer_29_11', 'php_4_13'];
    for (final pid in knownPassages) {
      final doc = await FirebaseFirestore.instance
          .collection('sparkcache')
          .doc(today)
          .collection(pid)
          .doc('kjv')
          .get();
      if (doc.exists && mounted) {
        final ref = doc.data()?['reference'] as String? ?? pid.replaceAll('_', ' ');
        setState(() {
          _passageId = pid;
          _passage = ref;
        });
        return;
      }
    }
  }

  String _formatStudyLevel(String raw) {
    switch (raw) {
      case 'growing': return 'Growing';
      case 'scholar': return 'Scholar';
      default: return 'Beginner';
    }
  }

  void _loadUserStats() {
    final uid = ref.read(authStreamProvider).valueOrNull?.uid ?? '';
    if (uid.isEmpty) return;
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data()!;
        final profile = data['profile'] as Map<String, dynamic>? ?? {};
        setState(() {
          _streak = profile['streak'] as int? ?? 0;
          _totalXp = profile['xp'] as int? ?? 0;
          // Daily XP: reset if date changed
          final today = DateTime.now().toIso8601String().split('T')[0];
          final xpDate = profile['xpTodayDate'] as String? ?? '';
          _dailyXp = xpDate == today ? (profile['xpToday'] as int? ?? 0) : 0;
          _studyLevel = _formatStudyLevel(profile['studyLevel'] as String? ?? 'beginner');
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: Column(
              children: [
                if (_showSparkHint)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GestureDetector(
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('hint_spark_session', true);
                        if (mounted) setState(() => _showSparkHint = false);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Text('⚡ ', style: TextStyle(fontSize: 16)),
                            const Expanded(
                              child: Text(
                                'A Spark is 90 seconds of focused study — a verse, an AI question, and your reflection. Tap to dismiss.',
                                style: TextStyle(fontSize: 12, color: AppColors.warmGold),
                              ),
                            ),
                            const Icon(Icons.close, size: 14, color: AppColors.warmGold),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(flex: 8, child: _QuestCard(
                  passage: _passage,
                  studyLevel: _studyLevel,
                  xpReward: _xpForLength(_sessionLength),
                  sessionLength: _sessionLength,
                  onLengthChanged: (l) => setState(() => _sessionLength = l),
                  onStart: _startSession,
                  onRandomSpark: _randomSpark,
                )),
                Expanded(flex: 2, child: _StatsBar(
                  streak: _streak,
                  dailyXp: _dailyXp.clamp(0, _dailyXpGoal),
                  dailyXpGoal: _dailyXpGoal,
                )),
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
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => SparkSessionScreen(
          passageId: _passageId,
          reference: _passage,
          version: 'kjv',
          sessionLength: _sessionLength,
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
  final String studyLevel;
  final int xpReward;
  final SessionLength sessionLength;
  final ValueChanged<SessionLength> onLengthChanged;
  final VoidCallback onStart;
  final VoidCallback onRandomSpark;

  const _QuestCard({
    required this.passage,
    required this.studyLevel,
    required this.xpReward,
    required this.sessionLength,
    required this.onLengthChanged,
    required this.onStart,
    required this.onRandomSpark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        key: WalkthroughKeys.questPassageCard,
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
                  child: Text(studyLevel, style: AppTypography.labelSmall),
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
              key: WalkthroughKeys.sessionToggle,
              selected: sessionLength,
              onChanged: onLengthChanged,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GestureDetector(
                onTap: onStart,
                child: Image.asset(
                  'assets/images/start_quest_button.png',
                  key: WalkthroughKeys.startQuestButton,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                key: WalkthroughKeys.randomSpark,
                onTap: onRandomSpark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/random_spark.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Random Spark',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.warmGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Jump to a surprise verse',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
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

  const _SessionToggle({super.key, required this.selected, required this.onChanged});

  static const _meta = {
    SessionLength.spark: ('Spark', '~90 sec', 'One verse + reflection'),
    SessionLength.short: ('Short', '~5 min', 'Verse + AI questions'),
    SessionLength.deep: ('Deep', '~10 min', 'Full study + journal'),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: SessionLength.values.map((l) {
          final isSelected = l == selected;
          final (label, time, desc) = _meta[l]!;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.warmGold : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSmall.copyWith(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 10,
                        color: isSelected ? Colors.white70 : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      desc,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: isSelected
                            ? Colors.white.withOpacity(0.75)
                            : AppColors.textSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
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

