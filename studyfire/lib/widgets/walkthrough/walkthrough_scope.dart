import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough/walkthrough_service.dart';
import 'coach_mark_overlay.dart';

/// Wraps the app shell body. Listens to walkthrough step changes and:
///   1. Navigates to the correct tab when the step's tabPath changes.
///   2. Renders the CoachMarkOverlay on top of everything.
class WalkthroughScope extends ConsumerStatefulWidget {
  final Widget child;
  const WalkthroughScope({super.key, required this.child});

  @override
  ConsumerState<WalkthroughScope> createState() => _WalkthroughScopeState();
}

class _WalkthroughScopeState extends ConsumerState<WalkthroughScope> {
  String? _lastTabPath;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walkthroughProvider);

    // When step changes and requires a different tab, navigate there.
    final step = state.step;
    if (state.isActive && step != null && step.tabPath != _lastTabPath) {
      _lastTabPath = step.tabPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(step.tabPath);
      });
    }

    if (!state.isActive) {
      _lastTabPath = null;
    }

    return Stack(
      children: [
        widget.child,
        if (state.isActive)
          Positioned.fill(
            child: CoachMarkOverlay(),
          ),
      ],
    );
  }
}
