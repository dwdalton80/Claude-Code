import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'walkthrough_keys.dart';

// ── Prefs key ─────────────────────────────────────────────────────────────────
const _kWalkthroughDone = 'walkthrough_done_v3';

// ── Step model ────────────────────────────────────────────────────────────────

enum TooltipPlacement { above, below, center }

class WalkthroughStep {
  final String title;
  final String body;
  final String tabPath;        // GoRouter path to navigate to before showing step
  final GlobalKey? targetKey;  // null ⇒ center modal (no spotlight)
  final TooltipPlacement placement;
  final double spotlightPadding;
  final double spotlightRadius;

  const WalkthroughStep({
    required this.title,
    required this.body,
    required this.tabPath,
    this.targetKey,
    this.placement = TooltipPlacement.above,
    this.spotlightPadding = 12,
    this.spotlightRadius = 16,
  });
}

// ── Step definitions ──────────────────────────────────────────────────────────

final _steps = <WalkthroughStep>[
  WalkthroughStep(
    title: "Today's Quest",
    body: "Every day a new Bible passage is waiting for you here. "
        "Start your study session to earn XP and build your streak.",
    tabPath: '/quest',
    targetKey: WalkthroughKeys.questPassageCard,
    placement: TooltipPlacement.below,
    spotlightPadding: 16,
    spotlightRadius: 24,
  ),
  WalkthroughStep(
    title: "Choose Your Session Length",
    body: "Pick how much time you have:\n"
        "• Spark — 90 seconds, one verse & reflection\n"
        "• Short — 5 minutes, verse + AI questions\n"
        "• Deep — 10 minutes, full study & journal",
    tabPath: '/quest',
    targetKey: WalkthroughKeys.sessionToggle,
    placement: TooltipPlacement.above,
    spotlightPadding: 10,
    spotlightRadius: 12,
  ),
  WalkthroughStep(
    title: "Start Your Quest",
    body: "Tap here when you're ready. You'll earn XP toward your next level!",
    tabPath: '/quest',
    targetKey: WalkthroughKeys.startQuestButton,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 12,
  ),
  WalkthroughStep(
    title: "Random Spark ⚡",
    body: "Feeling adventurous? Tap Random Spark to jump to a surprise verse "
        "for a quick 90-second devotional anytime.",
    tabPath: '/quest',
    targetKey: WalkthroughKeys.randomSpark,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 12,
  ),
  WalkthroughStep(
    title: "Study Groups 👥",
    body: "Study with your church or Bible study class! Create a group or join "
        "one with an invite code.\n\n"
        "Share notes, post questions, pray for each other 🙏, track streaks "
        "on the leaderboard, and grow together.",
    tabPath: '/groups',
    targetKey: WalkthroughKeys.groupsList,
    placement: TooltipPlacement.above,
    spotlightPadding: 16,
    spotlightRadius: 20,
  ),
  WalkthroughStep(
    title: "Games & Quiz",
    body: "Test your Bible knowledge! Choose a topic and challenge yourself "
        "with AI-generated questions. Each completed quiz earns XP.",
    tabPath: '/games',
    targetKey: WalkthroughKeys.quizTopicGrid,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 16,
  ),
  WalkthroughStep(
    title: "The Bible 📖",
    body: "Tap the title bar to jump to any book, chapter, or translation.\n\n"
        "Tap any verse to highlight it, ask AI for commentary, or save it "
        "to your Verse Vault. Tap New Note to journal right from what you're reading.",
    tabPath: '/reader',
    targetKey: WalkthroughKeys.readerToolbar,
    placement: TooltipPlacement.below,
    spotlightPadding: 8,
    spotlightRadius: 8,
  ),
  WalkthroughStep(
    title: "Tap Any Verse ✨",
    body: "Tap a verse to instantly pull up three quick actions:\n\n"
        "🖍  Highlight — color-code it for quick reference\n"
        "🤖  Ask AI — get context, commentary, and deeper meaning\n"
        "📚  Memorize — save it to your Verse Vault to practice\n\n"
        "Long-press for the full menu with even more options.",
    tabPath: '/reader',
    targetKey: WalkthroughKeys.readerContent,
    placement: TooltipPlacement.below,
    spotlightPadding: 12,
    spotlightRadius: 16,
  ),
  WalkthroughStep(
    title: "Your Profile & Streak",
    body: "Track your XP, level, and daily streak here. Keep showing up "
        "every day to protect your streak and level up!",
    tabPath: '/profile',
    targetKey: WalkthroughKeys.profileHero,
    placement: TooltipPlacement.below,
    spotlightPadding: 12,
    spotlightRadius: 20,
  ),
  WalkthroughStep(
    title: "Badges",
    body: "Earn badges for milestones — streaks, XP levels, quiz completions, "
        "and memorized verses. How many can you collect?",
    tabPath: '/profile',
    targetKey: WalkthroughKeys.profileBadges,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 16,
  ),
  WalkthroughStep(
    title: "Verse Vault 📖",
    body: "Every verse you memorize lives here. Tap any verse to keep "
        "practicing and move through all five mastery stages.",
    tabPath: '/profile',
    targetKey: WalkthroughKeys.profileVerseVault,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 16,
  ),
  WalkthroughStep(
    title: "Your Notes & Journal 📝",
    body: "Your sermon notes and Bible study entries live here.\n\n"
        "Tap any note to read it, or tap the arrow to open your full "
        "journal — where you can add Sermon Notes, Personal Study entries, "
        "and use ✨ AI to unpack what you learned.",
    tabPath: '/profile',
    targetKey: WalkthroughKeys.profileNotes,
    placement: TooltipPlacement.above,
    spotlightPadding: 12,
    spotlightRadius: 16,
  ),
];

// ── State ─────────────────────────────────────────────────────────────────────

class WalkthroughState {
  final bool isActive;
  final int currentStep;
  final int totalSteps;

  const WalkthroughState({
    required this.isActive,
    required this.currentStep,
    required this.totalSteps,
  });

  WalkthroughStep? get step =>
      isActive && currentStep < totalSteps ? _steps[currentStep] : null;

  bool get isLast => currentStep == totalSteps - 1;

  WalkthroughState copyWith({bool? isActive, int? currentStep}) =>
      WalkthroughState(
        isActive: isActive ?? this.isActive,
        currentStep: currentStep ?? this.currentStep,
        totalSteps: totalSteps,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class WalkthroughNotifier extends StateNotifier<WalkthroughState> {
  WalkthroughNotifier()
      : super(WalkthroughState(
          isActive: false,
          currentStep: 0,
          totalSteps: _steps.length,
        ));

  /// Call after user logs in. Starts walkthrough if it hasn't been seen.
  /// In debug builds, always resets so every flutter run shows the tour.
  Future<void> maybeStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (kDebugMode) {
      // Always show in debug so you can test without reinstalling
      await prefs.remove(_kWalkthroughDone);
    }
    final done = prefs.getBool(_kWalkthroughDone) ?? false;
    if (!done) {
      state = state.copyWith(isActive: true, currentStep: 0);
    }
  }

  /// Force-start regardless of prefs (for debug / re-run).
  void forceStart() {
    state = state.copyWith(isActive: true, currentStep: 0);
  }

  void next() {
    if (!state.isActive) return;
    if (state.isLast) {
      _finish();
    } else {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void skip() => _finish();

  Future<void> _finish() async {
    state = state.copyWith(isActive: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWalkthroughDone, true);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final walkthroughProvider =
    StateNotifierProvider<WalkthroughNotifier, WalkthroughState>(
  (ref) => WalkthroughNotifier(),
);
