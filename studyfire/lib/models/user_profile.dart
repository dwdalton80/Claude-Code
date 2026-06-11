import 'package:cloud_firestore/cloud_firestore.dart';

enum StudyLevel { beginner, growing, scholar }
enum BibleVersion { kjv, csb, niv }
enum SessionLength { spark, short, deep }
enum StudyGoal { readMore, understandDeeper, memorize, applySermons }
enum UserTheme { dark, light, sepia, auto }

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String? avatarUrl;
  final int level;
  final int xp;
  final int streak;
  final int longestStreak;
  final int totalStudyDays;
  final StudyLevel studyLevel;
  final StudyGoal? goal;
  final BibleVersion defaultVersion;
  final SessionLength sessionLength;
  final DateTime lastActiveDate;
  final bool hasGraceDayAvailable;
  final int streakFreezeCount;
  final bool isPremium;
  final String? subscriptionTier;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.level,
    required this.xp,
    required this.streak,
    required this.longestStreak,
    required this.totalStudyDays,
    required this.studyLevel,
    this.goal,
    required this.defaultVersion,
    this.sessionLength = SessionLength.spark,
    required this.lastActiveDate,
    required this.hasGraceDayAvailable,
    required this.streakFreezeCount,
    required this.isPremium,
    this.subscriptionTier,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      avatarUrl: data['avatarUrl'],
      level: data['level'] ?? 1,
      xp: data['xp'] ?? 0,
      streak: data['streak'] ?? 0,
      longestStreak: data['longestStreak'] ?? 0,
      totalStudyDays: data['totalStudyDays'] ?? 0,
      studyLevel: StudyLevel.values.firstWhere(
        (e) => e.name == data['studyLevel'],
        orElse: () => StudyLevel.beginner,
      ),
      goal: data['goal'] != null
          ? StudyGoal.values.firstWhere(
              (e) => e.name == data['goal'],
              orElse: () => StudyGoal.readMore,
            )
          : null,
      defaultVersion: BibleVersion.values.firstWhere(
        (e) => e.name == data['defaultVersion'],
        orElse: () => BibleVersion.niv,
      ),
      sessionLength: SessionLength.values.firstWhere(
        (e) => e.name == data['sessionLength'],
        orElse: () => SessionLength.spark,
      ),
      lastActiveDate: (data['lastActiveDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      hasGraceDayAvailable: data['hasGraceDayAvailable'] ?? true,
      streakFreezeCount: data['streakFreezeCount'] ?? 0,
      isPremium: data['isPremium'] ?? false,
      subscriptionTier: data['subscriptionTier'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'level': level,
        'xp': xp,
        'streak': streak,
        'longestStreak': longestStreak,
        'totalStudyDays': totalStudyDays,
        'studyLevel': studyLevel.name,
        'goal': goal?.name,
        'defaultVersion': defaultVersion.name,
        'sessionLength': sessionLength.name,
        'lastActiveDate': Timestamp.fromDate(lastActiveDate),
        'hasGraceDayAvailable': hasGraceDayAvailable,
        'streakFreezeCount': streakFreezeCount,
        'isPremium': isPremium,
        'subscriptionTier': subscriptionTier,
      };

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    int? level,
    int? xp,
    int? streak,
    int? longestStreak,
    int? totalStudyDays,
    StudyLevel? studyLevel,
    StudyGoal? goal,
    BibleVersion? defaultVersion,
    SessionLength? sessionLength,
    DateTime? lastActiveDate,
    bool? hasGraceDayAvailable,
    int? streakFreezeCount,
    bool? isPremium,
    String? subscriptionTier,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      streak: streak ?? this.streak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalStudyDays: totalStudyDays ?? this.totalStudyDays,
      studyLevel: studyLevel ?? this.studyLevel,
      goal: goal ?? this.goal,
      defaultVersion: defaultVersion ?? this.defaultVersion,
      sessionLength: sessionLength ?? this.sessionLength,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      hasGraceDayAvailable: hasGraceDayAvailable ?? this.hasGraceDayAvailable,
      streakFreezeCount: streakFreezeCount ?? this.streakFreezeCount,
      isPremium: isPremium ?? this.isPremium,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
    );
  }
}

class UserStats {
  final int totalVerses;
  final int wordsExplored;
  final int questionsAnswered;
  final int journalEntries;
  final int versesMemorized;

  const UserStats({
    required this.totalVerses,
    required this.wordsExplored,
    required this.questionsAnswered,
    required this.journalEntries,
    required this.versesMemorized,
  });

  factory UserStats.fromMap(Map<String, dynamic> data) => UserStats(
        totalVerses: data['totalVerses'] ?? 0,
        wordsExplored: data['wordsExplored'] ?? 0,
        questionsAnswered: data['questionsAnswered'] ?? 0,
        journalEntries: data['journalEntries'] ?? 0,
        versesMemorized: data['versesMemorized'] ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'totalVerses': totalVerses,
        'wordsExplored': wordsExplored,
        'questionsAnswered': questionsAnswered,
        'journalEntries': journalEntries,
        'versesMemorized': versesMemorized,
      };
}
