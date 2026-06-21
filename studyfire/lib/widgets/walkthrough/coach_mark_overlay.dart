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

    // Determine spotlight rect from GlobalKey, or use a default center rect
    Rect spotRect = Rect.fromCenter(
      center: Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
      width: 0,
      height: 0,
    );

    if (step.targetKey?.currentContext != null) {
      final renderBox =
          step.targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.attached && renderBox.hasSize) {
        try {
          final offset = renderBox.localToGlobal(Offset.zero);
          final size = renderBox.size;
          spotRect = Rect.fromLTWH(
            offset.dx - step.spotlightPadding,
            offset.dy - step.spotlightPadding,
            size.width + step.spotlightPadding * 2,
            size.height + step.spotlightPadding * 2,
          );
        } catch (_) {
          // Ancestor not yet laid out — use default centered rect this frame.
        }
      }
    }

    final screenSize = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Bottom nav bar height + safe area
    const navBarHeight = 60.0;
    final tooltipBottomOffset = navBarHeight + bottomInset + 8;

    // Decide whether to anchor tooltip above or below the spotlight.
    // Rule: if spotlight center is in the bottom half → show tooltip above it.
    //       Otherwise → pin to bottom above nav bar.
    final spotCenterY = spotRect.center.dy;
    final bool spotIsInBottomHalf = spotCenterY > screenSize.height * 0.5;

    double? tooltipTop;
    double? tooltipBottom;

    if (spotIsInBottomHalf) {
      // Tooltip above the spotlight
      tooltipBottom = screenSize.height - spotRect.top + 12;
      // Safety: never push tooltip off the top
      final maxBottom = screenSize.height - MediaQuery.of(context).padding.top - 80;
      tooltipBottom = tooltipBottom.clamp(tooltipBottomOffset, maxBottom);
    } else {
      // Tooltip pinned above bottom nav, arrow points up toward spotlight
      tooltipBottom = tooltipBottomOffset;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},  // swallow taps — only Next/Skip buttons work
      child: Stack(
        children: [
          // Spotlight overlay
          CustomPaint(
            size: screenSize,
            painter: _SpotlightPainter(
              spotRect: spotRect,
              radius: step.spotlightRadius,
            ),
          ),

          // Tooltip card
          Positioned(
            left: 0,
            right: 0,
            top: tooltipTop,
            bottom: tooltipBottom,
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

          // Pulsing ring on the long-press step to hint at the gesture
          if (step.targetKey == WalkthroughKeys.readerContent &&
              step.targetKey?.currentContext != null)
            _PulseRing(
              center: Offset(
                spotRect.left + 60, // offset to a verse position
                spotRect.top + spotRect.height * 0.25,
              ),
            ),

          // Arrow pointing from tooltip toward spotlight
          if (step.targetKey?.currentContext != null) ...[
            if (tooltipBottom != null && !spotIsInBottomHalf)
              // Tooltip at bottom, arrow points UP toward spotlight
              Positioned(
                left: spotRect.center.dx.clamp(20.0, screenSize.width - 40),
                bottom: tooltipBottom - 20,
                child: _Arrow(pointDown: false),
              ),
            if (tooltipBottom != null && spotIsInBottomHalf)
              // Tooltip above spotlight, arrow points DOWN toward spotlight
              Positioned(
                left: spotRect.center.dx.clamp(20.0, screenSize.width - 40),
                bottom: tooltipBottom - 20,
                child: _Arrow(pointDown: true),
              ),
          ],
        ],
      ),
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
