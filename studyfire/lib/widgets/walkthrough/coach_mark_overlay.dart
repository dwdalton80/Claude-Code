import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/walkthrough/walkthrough_keys.dart';
import '../../core/walkthrough/walkthrough_service.dart';

// ── Painter: spotlight cutout ─────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect spotRect;
  final double radius;

  const _SpotlightPainter({required this.spotRect, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withOpacity(0.75);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Draw overlay with rounded rect hole
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(fullRect)
      ..addRRect(RRect.fromRectAndRadius(spotRect, Radius.circular(radius)));

    canvas.drawPath(path, overlay);

    // Subtle golden glow border around spotlight
    final borderPaint = Paint()
      ..color = AppColors.warmGold.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(spotRect, Radius.circular(radius)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.spotRect != spotRect || old.radius != radius;
}

// ── Tooltip card ──────────────────────────────────────────────────────────────

class _TooltipCard extends StatelessWidget {
  final WalkthroughStep step;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TooltipCard({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = currentStep == totalSteps - 1;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: AppColors.warmGold.withOpacity(0.12),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step counter
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${currentStep + 1} of $totalSteps',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.warmGold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onSkip,
                  child: Text(
                    'Skip tour',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              step.title,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),

            // Body
            Text(
              step.body,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // Progress dots + Next button
            Row(
              children: [
                // Dots
                ...List.generate(totalSteps, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 5),
                  width: i == currentStep ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == currentStep
                        ? AppColors.warmGold
                        : AppColors.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
                const Spacer(),

                // Next / Finish button
                GestureDetector(
                  onTap: onNext,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.warmGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isLast ? "Let's go! 🔥" : 'Next',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

// ── Main overlay widget ───────────────────────────────────────────────────────

class CoachMarkOverlay extends ConsumerWidget {
  const CoachMarkOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walkthroughProvider);
    final notifier = ref.read(walkthroughProvider.notifier);

    if (!state.isActive || state.step == null) return const SizedBox.shrink();

    final step = state.step!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // availableSize = the actual body area (excludes status bar + nav bar)
        final availableSize = constraints.biggest;

        // Determine spotlight rect in the overlay's LOCAL coordinate space.
        Rect spotRect = Rect.fromCenter(
          center: Offset(availableSize.width / 2, availableSize.height / 2),
          width: 0,
          height: 0,
        );

        if (step.targetKey?.currentContext != null) {
          final targetBox =
              step.targetKey!.currentContext!.findRenderObject() as RenderBox?;
          final overlayBox = context.findRenderObject() as RenderBox?;
          if (targetBox != null && targetBox.attached && targetBox.hasSize &&
              overlayBox != null && overlayBox.attached) {
            try {
              // Convert to overlay-local coords so painting aligns with layout.
              final localOffset =
                  targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
              final size = targetBox.size;
              spotRect = Rect.fromLTWH(
                localOffset.dx - step.spotlightPadding,
                localOffset.dy - step.spotlightPadding,
                size.width + step.spotlightPadding * 2,
                size.height + step.spotlightPadding * 2,
              );
            } catch (_) {
              // ancestor not yet laid out — use default centered rect
            }
          }
        }

        final spotCenterY = spotRect.center.dy;
        final bool spotIsInBottomHalf =
            spotCenterY > availableSize.height * 0.5;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // swallow background taps
          child: Stack(
            children: [
              // Dark overlay with spotlight cutout
              CustomPaint(
                size: availableSize,
                painter: _SpotlightPainter(
                  spotRect: spotRect,
                  radius: step.spotlightRadius,
                ),
              ),

              // Tooltip card — always anchored to the bottom of the body area.
              // Align is coordinate-system agnostic so it always works correctly.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: KeyedSubtree(
                      key: ValueKey(state.currentStep),
                      child: _TooltipCard(
                        step: step,
                        currentStep: state.currentStep,
                        totalSteps: state.totalSteps,
                        onNext: notifier.next,
                        onSkip: notifier.skip,
                      ),
                    ),
                  ),
                ),
              ),

              // Pulsing ring on the tap-a-verse step
              if (step.targetKey == WalkthroughKeys.readerContent &&
                  step.targetKey?.currentContext != null)
                _PulseRing(
                  center: Offset(
                    spotRect.left + 60,
                    spotRect.top + spotRect.height * 0.25,
                  ),
                ),

              // Arrow pointing toward spotlight
              if (step.targetKey?.currentContext != null)
                Positioned(
                  left: spotRect.center.dx
                      .clamp(20.0, availableSize.width - 40)
                      .toDouble(),
                  bottom: spotIsInBottomHalf
                      ? availableSize.height - spotRect.top + 4
                      : 200, // ~above the card
                  child: _Arrow(
                    pointDown: !spotIsInBottomHalf,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Arrow extends StatelessWidget {
  final bool pointDown;
  const _Arrow({required this.pointDown});

  @override
  Widget build(BuildContext context) {
    return Icon(
      pointDown ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
      color: AppColors.warmGold.withOpacity(0.8),
      size: 24,
    );
  }
}

// ── Pulsing "hold here" indicator ─────────────────────────────────────────────

class _PulseRing extends StatefulWidget {
  final Offset center;
  const _PulseRing({required this.center});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _scale = Tween<double>(begin: 0.6, end: 1.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Positioned(
          left: widget.center.dx - 28,
          top: widget.center.dy - 28,
          child: Opacity(
            opacity: _opacity.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.warmGold,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
