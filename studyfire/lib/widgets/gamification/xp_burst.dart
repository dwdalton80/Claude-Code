import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';

class XpBurstOverlay extends StatefulWidget {
  final int xp;
  final VoidCallback? onComplete;

  const XpBurstOverlay({super.key, required this.xp, this.onComplete});

  @override
  State<XpBurstOverlay> createState() => _XpBurstOverlayState();
}

class _XpBurstOverlayState extends State<XpBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));

    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scale = Tween<double>(begin: 0.3, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );

    _slide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.5),
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)),
    );

    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );

    _ctrl.forward().then((_) => widget.onComplete?.call());

    HapticFeedback.heavyImpact();
    _confetti.play();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            colors: const [
              AppColors.warmGold,
              AppColors.flameOrange,
              AppColors.emerald,
              Colors.white,
            ],
            numberOfParticles: 30,
            gravity: 0.3,
          ),
        ),
        Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: AppColors.flameCTAGradient,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.warmGold.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      '+${widget.xp} XP',
                      style: AppTypography.xpLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StreakDisplay extends StatelessWidget {
  final int streak;
  final bool large;

  const StreakDisplay({super.key, required this.streak, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🔥', style: TextStyle(fontSize: large ? 36 : 22)),
        const SizedBox(width: 4),
        Text(
          streak.toString(),
          style: large ? AppTypography.streakNumber : AppTypography.xpLabel,
        ),
        if (!large) ...[
          const SizedBox(width: 4),
          Text(
            'day streak',
            style: AppTypography.bodySmall,
          ),
        ],
      ],
    );
  }
}
