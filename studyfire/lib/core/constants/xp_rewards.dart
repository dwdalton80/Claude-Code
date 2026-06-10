class XpRewards {
  XpRewards._();

  static const int openAppDaily = 5;
  static const int completeSparkSession = 15;
  static const int completeShortSession = 25;
  static const int completeDeepSession = 40;
  static const int answerAiQuestion = 10;
  static const int addJournalEntry = 15;
  static const int wordOfDayTap = 10;
  static const int sevenDayStreakBonus = 50;
  static const int shareVerse = 5;
  static const int markApplicationDone = 20;
  static const int shareNoteToGroup = 10;
  static const int postQuestionToGroup = 10;
  static const int commentOnGroupQuestion = 5;
  static const int earn5ReactionsBonus = 15;

  // Memory Verse
  static const int memoryStage1 = 5;
  static const int memoryStage2 = 10;
  static const int memoryStage2Bonus = 5;
  static const int memoryStage3 = 15;
  static const int memoryStage3Bonus = 10;
  static const int memoryStage4 = 20;
  static const int memoryStage4Bonus = 15;
  static const int memoryStage5 = 30;
  static const int memoryStage5PerfectBonus = 20;

  // Journal
  static const int createNote = 15;
  static const int generateDebrief = 15;
  static const int shareDiscussionQuestion = 5;
  static const int add3ScriptureRefs = 10;

  // Quiz
  static const int completeQuiz = 25;
  static const int perfectScoreBonus = 50;
  static const int sevenDayQuizStreak = 75;

  // Streak protection
  static const int readVerse = 5;
}

class XpMilestones {
  XpMilestones._();

  static const Map<int, String> badges = {
    100: 'spark',
    500: 'on_fire',
    1500: 'burning_bright',
    3500: 'unquenchable',
    7000: 'flame_keeper',
    12000: 'eternal_flame',
  };
}

class LevelThresholds {
  LevelThresholds._();

  static const List<Map<String, dynamic>> levels = [
    {'level': 1, 'name': 'Seeker', 'xp': 0, 'unlock': 'Default flame theme'},
    {'level': 2, 'name': 'Disciple', 'xp': 500, 'unlock': 'Gold profile frame'},
    {'level': 3, 'name': 'Scribe', 'xp': 1500, 'unlock': 'Parchment theme + quill icon set'},
    {'level': 4, 'name': 'Scholar', 'xp': 3500, 'unlock': 'Deep Indigo theme + scholar frame'},
    {'level': 5, 'name': 'Teacher', 'xp': 7000, 'unlock': 'Crimson theme + public note sharing'},
    {'level': 6, 'name': 'Sage', 'xp': 12000, 'unlock': 'Obsidian theme + animated badge'},
    {'level': 7, 'name': 'Elder', 'xp': 20000, 'unlock': 'Platinum theme + Elder crown badge'},
  ];

  static Map<String, dynamic> forXp(int xp) {
    Map<String, dynamic> current = levels.first;
    for (final level in levels) {
      if (xp >= (level['xp'] as int)) {
        current = level;
      }
    }
    return current;
  }

  static int? nextThreshold(int xp) {
    for (final level in levels) {
      if ((level['xp'] as int) > xp) return level['xp'] as int;
    }
    return null;
  }
}
