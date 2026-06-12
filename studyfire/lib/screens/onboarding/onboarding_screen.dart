import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/auth_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/progress_bar.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  int _step = 0;
  BibleVersion? _selectedVersion;
  StudyGoal? _selectedGoal;
  String? _selectedReminder;
  bool _isLoading = false;

  late final AnimationController _flameController;
  late final Animation<double> _flamePulse;

  @override
  void initState() {
    super.initState();
    _flameController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _flamePulse = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _flameController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flameController.dispose();
    super.dispose();
  }

  void _advance() => setState(() => _step++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: switch (_step) {
              0 => _WelcomeStep(flamePulse: _flamePulse, onStart: _advance),
              1 => _VersionStep(onSelect: (v) { _selectedVersion = v; _advance(); }),
              2 => _GoalStep(onSelect: (g) { _selectedGoal = g; _advance(); }),
              3 => _ReminderStep(onSelect: (r) { _selectedReminder = r; _advance(); }),
              4 => _AccountStep(
                  onComplete: _completeOnboarding,
                  isLoading: _isLoading,
                ),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);
    // Navigation handled by auth state change listener in router
  }
}

// ── Step 1: Welcome ──────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  final Animation<double> flamePulse;
  final VoidCallback onStart;

  const _WelcomeStep({required this.flamePulse, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          ScaleTransition(
            scale: flamePulse,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B00).withOpacity(0.5),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'StudyFire',
            style: AppTypography.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Ignite your study.\nEvery day.',
            style: AppTypography.displaySmall.copyWith(
              color: AppColors.warmGold,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Takes about 90 seconds',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const Spacer(flex: 3),
          FlameCTAButton(
            label: 'Let\'s go 🔥',
            onPressed: onStart,
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ── Step 2: Bible Version ────────────────────────────────────────────────────

class _VersionStep extends StatelessWidget {
  final ValueChanged<BibleVersion> onSelect;

  const _VersionStep({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepProgress(current: 2, total: 5),
          const SizedBox(height: 40),
          const Text(
            'Which Bible translation\ndo you prefer?',
            style: AppTypography.displayMedium,
          ),
          const SizedBox(height: 32),
          _VersionCard(
            label: 'KJV',
            subtitle: 'King James Version — Traditional',
            onTap: () => onSelect(BibleVersion.kjv),
          ),
          const SizedBox(height: 12),
          _VersionCard(
            label: 'CSB',
            subtitle: 'Christian Standard Bible — Balanced',
            onTap: () => onSelect(BibleVersion.csb),
          ),
          const SizedBox(height: 12),
          _VersionCard(
            label: 'NIV',
            subtitle: 'New International Version — Accessible',
            onTap: () => onSelect(BibleVersion.niv),
          ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _VersionCard({required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Text(label, style: AppTypography.labelLarge.copyWith(fontSize: 20)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(subtitle, style: AppTypography.bodySmall),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Step 3: Goal ─────────────────────────────────────────────────────────────

class _GoalStep extends StatelessWidget {
  final ValueChanged<StudyGoal> onSelect;

  const _GoalStep({required this.onSelect});

  static const _goals = [
    (StudyGoal.readMore, 'I want to read more', '📖'),
    (StudyGoal.understandDeeper, 'I want to understand deeper', '🔍'),
    (StudyGoal.memorize, 'I want to memorize Scripture', '🧠'),
    (StudyGoal.applySermons, 'I want to apply what I hear on Sundays', '✝️'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepProgress(current: 3, total: 5),
          const SizedBox(height: 40),
          const Text("What's your main goal?", style: AppTypography.displayMedium),
          const SizedBox(height: 32),
          ..._goals.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GoalCard(
                  emoji: g.$3,
                  label: g.$2,
                  onTap: () => onSelect(g.$1),
                ),
              )),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onSelect(StudyGoal.readMore),
              child: const Text('Skip', style: AppTypography.bodySmall),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _GoalCard({required this.emoji, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: AppTypography.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

// ── Step 4: Reminder ──────────────────────────────────────────────────────────

class _ReminderStep extends StatelessWidget {
  final ValueChanged<String?> onSelect;

  const _ReminderStep({required this.onSelect});

  static const _options = [
    ('morning', '☀️', 'Morning', '8–9 AM'),
    ('lunch', '🌤', 'Lunch', '12 PM'),
    ('evening', '🌙', 'Evening', '7–8 PM'),
    ('none', '❌', 'No thanks', 'Skip reminders'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepProgress(current: 4, total: 5),
          const SizedBox(height: 40),
          const Text('When should we\nremind you?', style: AppTypography.displayMedium),
          const SizedBox(height: 32),
          ..._options.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReminderCard(
                  id: o.$1,
                  emoji: o.$2,
                  label: o.$3,
                  subtitle: o.$4,
                  onTap: () => onSelect(o.$1 == 'none' ? null : o.$1),
                ),
              )),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final String id;
  final String emoji;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ReminderCard({
    required this.id,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.labelMedium),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 5: Account ───────────────────────────────────────────────────────────

class _AccountStep extends ConsumerWidget {
  final Future<void> Function() onComplete;
  final bool isLoading;

  const _AccountStep({required this.onComplete, required this.isLoading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = AuthService();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _StepProgress(current: 5, total: 5),
          const Spacer(),
          const Text('Save your progress', style: AppTypography.displayMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Your streaks, XP, and study history sync across devices.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          // Sign in with Apple
          _AuthButton(
            icon: Icons.apple,
            label: 'Sign in with Apple',
            isPrimary: true,
            onPressed: isLoading ? null : () async {
              try {
                await auth.signInWithApple();
                await onComplete();
              } catch (_) {}
            },
          ),
          const SizedBox(height: 12),
          // Sign in with Google
          _AuthButton(
            icon: Icons.g_mobiledata,
            label: 'Sign in with Google',
            isPrimary: false,
            onPressed: isLoading ? null : () async {
              try {
                await auth.signInWithGoogle();
                await onComplete();
              } catch (_) {}
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: isLoading
                  ? null
                  : () => _showEmailSheet(context, auth, onComplete),
              child: Text(
                'Continue with Email',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.warmGold,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.warmGold,
                ),
              ),
            ),
          ),
          if (isLoading) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ],
          const Spacer(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEmailSheet(
    BuildContext context,
    AuthService auth,
    Future<void> Function() onComplete,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EmailSignInSheet(auth: auth, onComplete: onComplete),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onPressed;

  const _AuthButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: AppTypography.button.copyWith(color: AppColors.textPrimary),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
    );
  }
}

class _EmailSignInSheet extends StatefulWidget {
  final AuthService auth;
  final Future<void> Function() onComplete;

  const _EmailSignInSheet({required this.auth, required this.onComplete});

  @override
  State<_EmailSignInSheet> createState() => _EmailSignInSheetState();
}

class _EmailSignInSheetState extends State<_EmailSignInSheet> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignUp = true;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isSignUp ? 'Create Account' : 'Sign In',
            style: AppTypography.displaySmall,
          ),
          const SizedBox(height: 24),
          if (_isSignUp)
            TextField(
              controller: _nameCtrl,
              style: AppTypography.bodyLarge,
              decoration: const InputDecoration(hintText: 'Your name'),
            ),
          if (_isSignUp) const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(hintText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(hintText: 'Password'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          FlameCTAButton(
            label: _isSignUp ? 'Create Account' : 'Sign In',
            isLoading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _isSignUp = !_isSignUp),
            child: Text(
              _isSignUp ? 'Already have an account? Sign in' : 'Need an account? Sign up',
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await widget.auth.createAccountWithEmail(
          _emailCtrl.text.trim(),
          _passCtrl.text,
          _nameCtrl.text.trim(),
        );
      } else {
        await widget.auth.signInWithEmail(
          _emailCtrl.text.trim(),
          _passCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
      await widget.onComplete();
    } on Exception catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final int current;
  final int total;

  const _StepProgress({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: current / total,
                backgroundColor: AppColors.surface,
                valueColor: const AlwaysStoppedAnimation(AppColors.warmGold),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$current of $total',
              style: AppTypography.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}
