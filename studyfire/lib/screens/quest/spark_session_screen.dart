import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/session_length.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/xp_service.dart';
import '../../core/services/streak_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';
import '../../core/services/group_activity_service.dart';
import '../../app.dart';
import 'package:confetti/confetti.dart';
import 'package:go_router/go_router.dart';
import '../journal/journal_screen.dart';

class SparkSessionScreen extends ConsumerStatefulWidget {
  final String passageId; // e.g. "rom_8_28"
  final String reference; // e.g. "Romans 8:28"
  final String version;
  final SessionLength sessionLength;

  const SparkSessionScreen({
    super.key,
    required this.passageId,
    required this.reference,
    required this.version,
    this.sessionLength = SessionLength.spark,
  });

  @override
  ConsumerState<SparkSessionScreen> createState() => _SparkSessionScreenState();
}

class _SparkSessionScreenState extends ConsumerState<SparkSessionScreen>
    with TickerProviderStateMixin {
  final _db = FirestoreService();
  final _xpService = XpService();
  final _streakService = StreakService();
  final _firestore = FirebaseFirestore.instance;

  String? _verseText;
  String? _question;
  String? _reflection;
  bool _loading = true;
  bool _showQuestion = false;
  bool _showResponse = false;
  bool _completed = false;
  StreakUpdateResult? _streakResult;
  List<String> _newBadges = [];

  final _responseController = TextEditingController();
  late AnimationController _progressController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _sparkDuration = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _sparkDuration,
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _loadSpark();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _fadeController.dispose();
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _loadSpark() async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    try {
      final snap = await _firestore
          .collection('sparkcache')
          .doc(today)
          .collection(widget.passageId)
          .doc(widget.version)
          .get()
          .timeout(const Duration(seconds: 5));

      if (snap.exists && mounted) {
        final data = snap.data()!;
        setState(() {
          _verseText = data['text'] as String?;
          _question = data['question'] as String?;
          _reflection = data['reflection'] as String?;
          _loading = false;
        });
        _fadeController.forward();
        // Show question after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showQuestion = true);
        });
        // Start progress bar
        _progressController.forward();
        // Show response after 60 seconds
        Future.delayed(const Duration(seconds: 60), () {
          if (mounted) setState(() => _showResponse = true);
        });
      } else if (mounted) {
        debugPrint("SparkSession: snap.exists=${snap.exists}, passageId=${widget.passageId}, version=${widget.version}, today=$today");
        // No cached spark — show verse only
        setState(() {
          _verseText = null;
          _question = 'What does this passage mean for your life today?';
          _loading = false;
        });
        _fadeController.forward();
        _progressController.forward();
      }
    } catch (e) {
      debugPrint("SparkSession error: $e");
      if (mounted) {
        setState(() {
          _question = 'What does this passage mean for your life today?';
          _loading = false;
        });
        _fadeController.forward();
        _progressController.forward();
      }
    }
  }

  Future<void> _complete() async {
    final uid = ref.read(authStreamProvider).valueOrNull?.uid ?? '';
    if (uid.isNotEmpty) {
      _xpService.accumulateXp(uid, XpRewards.completeSparkSession);
      final xpResult = await _xpService.flushSession(uid);
      _newBadges = xpResult.newBadges;

      // Record today's study activity — updates streak, longest streak,
      // grace day, and totalStudyDays. Idempotent: a no-op if already
      // recorded today. This is what makes the streak actually increment.
      try {
        _streakResult = await _streakService.recordActivity(uid);
        // Award streak milestone bonus XP
        if (_streakResult?.milestoneReached != null) {
          _xpService.accumulateXp(uid, XpRewards.sevenDayStreakBonus);
          final bonusResult = await _xpService.flushSession(uid);
          _newBadges = [..._newBadges, ...bonusResult.newBadges];
        }
      } catch (_) {
        // Non-fatal — XP still saved even if streak write fails
      }

      if (_responseController.text.trim().isNotEmpty) {
        await _firestore.collection('journal').doc(uid).collection('entries').add({
          'type': 'spark',
          'reference': widget.reference,
          'response': _responseController.text.trim(),
          'question': _question,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Post to group feeds
      final user = FirebaseAuth.instance.currentUser;
      final authorName = user?.displayName ?? user?.email?.split('@')[0] ?? 'Member';
      final sparkRef = widget.reference;
      // Update weekly XP in all groups
      GroupActivityService().updateMemberWeeklyXp(uid, XpRewards.completeSparkSession).catchError((_) {});
      GroupActivityService().postActivityToUserGroups(uid, authorName, FeedItemType.streakMilestone, {
        'text': authorName + ' completed a Spark session on ' + sparkRef + ' 🔥',
        'reference': sparkRef,
        'xp': XpRewards.completeSparkSession,
      }).catchError((_) {});
      _firestore.collection('users').doc(uid).update({
        'profile.questionsAnswered': FieldValue.increment(1),
      }).catchError((_) {});
    }
    if (mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) return _CompletionScreen(
      reference: widget.reference,
      passageId: widget.passageId,
      verseText: _verseText ?? '',
      version: widget.version,
      xp: XpRewards.completeSparkSession,
      streak: _streakResult?.newStreak,
      milestoneReached: _streakResult?.milestoneReached,
      newBadges: _newBadges,
      sessionLength: widget.sessionLength,
      onDone: () => Navigator.pop(context),
    );

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    // Progress bar
                    _SparkProgressBar(controller: _progressController),

                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: AppColors.textSecondary),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.warmGold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '⚡ SPARK',
                              style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Reference
                            Text(
                              widget.reference,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.warmGold,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Verse text
                            if (_verseText != null) ...[
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.cardDark,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.surface),
                                ),
                                child: Text(
                                  '"$_verseText"',
                                  style: AppTypography.verseText.copyWith(
                                    fontSize: 18,
                                    height: 1.7,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // AI Question
                            if (_showQuestion && _question != null) ...[
                              AnimatedOpacity(
                                opacity: _showQuestion ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 800),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'REFLECT',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppColors.textSecondary,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _question!,
                                      style: AppTypography.bodyLarge.copyWith(
                                        fontSize: 18,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Reflection context
                            if (_showQuestion && _reflection != null) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border(
                                    left: BorderSide(
                                      color: AppColors.warmGold,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _reflection!,
                                  style: AppTypography.bodySmall.copyWith(
                                    fontStyle: FontStyle.italic,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Response input
                            if (_showResponse) ...[
                              AnimatedOpacity(
                                opacity: _showResponse ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 800),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'YOUR RESPONSE (optional)',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppColors.textSecondary,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _responseController,
                                      maxLines: 4,
                                      style: AppTypography.bodyMedium,
                                      decoration: InputDecoration(
                                        hintText: 'Write a thought, prayer, or observation…',
                                        hintStyle: AppTypography.bodySmall.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                        filled: true,
                                        fillColor: AppColors.cardDark,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: AppColors.surface),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: AppColors.surface),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FlameCTAButton(
                                      label: 'Complete Spark  +${XpRewards.completeSparkSession} XP',
                                      onPressed: _complete,
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Done button always visible after question shows
                            if (_showQuestion && !_showResponse) ...[
                              const SizedBox(height: 24),
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    setState(() => _showResponse = true);
                                  },
                                  child: Text(
                                    'I\'m done reflecting →',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.warmGold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SparkProgressBar extends StatelessWidget {
  final AnimationController controller;
  const _SparkProgressBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => LinearProgressIndicator(
        value: controller.value,
        backgroundColor: AppColors.surface,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.warmGold),
        minHeight: 3,
      ),
    );
  }
}

class _CompletionScreen extends StatefulWidget {
  final String reference;
  final String passageId;
  final String verseText;
  final String version;
  final int xp;
  final int? streak;
  final int? milestoneReached;
  final List<String> newBadges;
  final SessionLength sessionLength;
  final VoidCallback onDone;

  const _CompletionScreen({
    required this.reference,
    required this.passageId,
    required this.verseText,
    required this.version,
    required this.xp,
    required this.streak,
    required this.milestoneReached,
    required this.newBadges,
    required this.sessionLength,
    required this.onDone,
  });

  @override
  State<_CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<_CompletionScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.newBadges.isNotEmpty) {
      // Show badge celebration after a short delay so the completion screen renders first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _showBadgeCelebration(widget.newBadges.first);
        });
      });
    }
  }

  void _showBadgeCelebration(String badgeId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BadgeCelebrationDialog(
        badgeId: badgeId,
        onDone: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStreak = widget.streak != null && widget.streak! > 0;
    final hitMilestone = widget.milestoneReached != null;

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 24),
                Text(
                  hitMilestone ? '${widget.milestoneReached}-Day Streak!' : 'Spark Complete!',
                  style: AppTypography.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.reference,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
                ),
                const SizedBox(height: 8),
                Text(
                  '+${widget.xp} XP earned',
                  style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold),
                ),
                if (hasStreak) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.warmGold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.streak} day${widget.streak == 1 ? '' : 's'} in a row',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.warmGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 48),
                if (widget.sessionLength == SessionLength.spark) ...[
                  FlameCTAButton(
                    label: 'Done',
                    onPressed: widget.onDone,
                  ),
                ] else if (widget.sessionLength == SessionLength.short) ...[
                  FlameCTAButton(
                    label: 'Go Deeper →',
                    onPressed: () {
                      widget.onDone();
                      Future.microtask(() {
                        if (context.mounted) {
                          context.push('/ai-study', extra: {
                            'passage': widget.verseText,
                            'reference': widget.reference,
                            'version': widget.version,
                            'passageId': widget.passageId,
                          });
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Skip — I\'m done', style: AppTypography.bodySmall),
                  ),
                ] else ...[
                  // Deep — AI Study + Journal
                  FlameCTAButton(
                    label: 'Go Deeper →',
                    onPressed: () {
                      widget.onDone();
                      Future.microtask(() {
                        if (context.mounted) {
                          context.push('/ai-study', extra: {
                            'passage': widget.verseText,
                            'reference': widget.reference,
                            'version': widget.version,
                            'passageId': widget.passageId,
                          });
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      widget.onDone();
                      Future.microtask(() {
                        if (context.mounted) {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => NoteEditorScreen(
                                verseRef: widget.reference,
                                verseText: widget.verseText,
                              ),
                            ),
                          );
                        }
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: AppColors.indigoAccent.withOpacity(0.6)),
                      foregroundColor: AppColors.warmWhite,
                    ),
                    child: const Text('Add Journal Entry'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Skip — I\'m done', style: AppTypography.bodySmall),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Badge Celebration Dialog ──────────────────────────────────────────────────

class _BadgeCelebrationDialog extends StatefulWidget {
  final String badgeId;
  final VoidCallback onDone;

  const _BadgeCelebrationDialog({required this.badgeId, required this.onDone});

  @override
  State<_BadgeCelebrationDialog> createState() => _BadgeCelebrationDialogState();
}

class _BadgeCelebrationDialogState extends State<_BadgeCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  static const _badgeInfo = {
    'spark':           ('Spark',          'assets/images/badges/badge_spark.png',          '100 XP milestone'),
    'on_fire':         ('On Fire',         'assets/images/badges/badge_on_fire.png',         '500 XP milestone'),
    'burning_bright':  ('Burning Bright',  'assets/images/badges/badge_burning_bright.png',  '1,500 XP milestone'),
    'unquenchable':    ('Unquenchable',    'assets/images/badges/badge_unquenchable.png',    '3,500 XP milestone'),
    'flame_keeper':    ('Flame Keeper',    'assets/images/badges/badge_flame_keeper.png',    '7,000 XP milestone'),
    'eternal_flame':   ('Eternal Flame',   'assets/images/badges/badge_eternal_flame.png',   '12,000 XP milestone'),
    'first_verse':     ('First Verse',     'assets/images/badges/badge_first_verse.png',     'First verse memorized'),
    'ten_verses':      ('Ten Verses',      'assets/images/badges/badge_ten_verses.png',      '10 verses memorized'),
    'comeback':        ('Comeback',        'assets/images/badges/badge_comeback.png',        'Returned after 7+ days'),
  };

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3))..play();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
    _scaleCtrl.forward();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _badgeInfo[widget.badgeId];
    final name = info?.$1 ?? 'Badge Earned';
    final imagePath = info?.$2 ?? 'assets/images/badges/badge_spark.png';
    final subtitle = info?.$3 ?? 'Achievement unlocked';

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Confetti behind the dialog
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          colors: const [
            AppColors.warmGold,
            AppColors.flameOrange,
            AppColors.emerald,
            Colors.white,
          ],
          numberOfParticles: 40,
          gravity: 0.3,
        ),
        Dialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🏆 Badge Earned!',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.warmGold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                ScaleTransition(
                  scale: _scale,
                  child: Image.asset(imagePath, width: 120, height: 120),
                ),
                const SizedBox(height: 20),
                Text(
                  name,
                  style: AppTypography.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FlameCTAButton(
                  label: 'Awesome! 🔥',
                  onPressed: widget.onDone,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
