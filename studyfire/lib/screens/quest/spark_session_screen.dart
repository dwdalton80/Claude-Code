import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../app.dart';

class SparkSessionScreen extends ConsumerStatefulWidget {
  final String passageId; // e.g. "rom_8_28"
  final String reference; // e.g. "Romans 8:28"
  final String version;

  const SparkSessionScreen({
    super.key,
    required this.passageId,
    required this.reference,
    required this.version,
  });

  @override
  ConsumerState<SparkSessionScreen> createState() => _SparkSessionScreenState();
}

class _SparkSessionScreenState extends ConsumerState<SparkSessionScreen>
    with TickerProviderStateMixin {
  final _db = FirestoreService();
  final _xpService = XpService();
  final _firestore = FirebaseFirestore.instance;

  String? _verseText;
  String? _question;
  String? _reflection;
  bool _loading = true;
  bool _showQuestion = false;
  bool _showResponse = false;
  bool _completed = false;

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
          .get();

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
      if (_responseController.text.trim().isNotEmpty) {
        await _firestore.collection('journal').doc(uid).collection('entries').add({
          'type': 'spark',
          'reference': widget.reference,
          'response': _responseController.text.trim(),
          'question': _question,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    if (mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) return _CompletionScreen(
      reference: widget.reference,
      xp: XpRewards.completeSparkSession,
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

class _CompletionScreen extends StatelessWidget {
  final String reference;
  final int xp;
  final VoidCallback onDone;

  const _CompletionScreen({
    required this.reference,
    required this.xp,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
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
                  'Spark Complete!',
                  style: AppTypography.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  reference,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
                ),
                const SizedBox(height: 8),
                Text(
                  '+$xp XP earned',
                  style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold),
                ),
                const SizedBox(height: 48),
                FlameCTAButton(
                  label: 'Done',
                  onPressed: onDone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
