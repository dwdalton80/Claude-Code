import 'package:flutter/widgets.dart';

/// Central registry of GlobalKeys used by the coach mark walkthrough.
/// Each key is attached to a specific widget so the overlay can calculate
/// its on-screen position and draw a spotlight around it.
class WalkthroughKeys {
  WalkthroughKeys._();

  // Quest Tab
  static final questPassageCard = GlobalKey(debugLabel: 'wt_questPassageCard');
  static final sessionToggle    = GlobalKey(debugLabel: 'wt_sessionToggle');
  static final startQuestButton = GlobalKey(debugLabel: 'wt_startQuestButton');
  static final randomSpark      = GlobalKey(debugLabel: 'wt_randomSpark');

  // Reader Tab
  static final readerContent = GlobalKey(debugLabel: 'wt_readerContent');
  static final readerToolbar = GlobalKey(debugLabel: 'wt_readerToolbar');

  // Groups Tab
  static final groupsList = GlobalKey(debugLabel: 'wt_groupsList');

  // Games / Quiz Tab
  static final quizTopicGrid = GlobalKey(debugLabel: 'wt_quizTopicGrid');

  // Profile Tab
  static final profileHero       = GlobalKey(debugLabel: 'wt_profileHero');
  static final profileBadges     = GlobalKey(debugLabel: 'wt_profileBadges');
  static final profileVerseVault = GlobalKey(debugLabel: 'wt_profileVerseVault');
  static final profileNotes      = GlobalKey(debugLabel: 'wt_profileNotes');
}
