import 'package:cloud_firestore/cloud_firestore.dart';

class StreakService {
  final _firestore = FirebaseFirestore.instance;

  Future<StreakUpdateResult> recordActivity(String uid) async {
    final ref = _firestore.collection('users').doc(uid);

    late StreakUpdateResult result;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = (snap.data() as Map<String, dynamic>?) ?? {};
      final profile = (data['profile'] as Map<String, dynamic>?) ?? {};

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final lastActiveTstamp = profile['lastActiveDate'] as Timestamp?;
      final lastActive = lastActiveTstamp?.toDate();
      final lastActiveDay = lastActive != null
          ? DateTime(lastActive.year, lastActive.month, lastActive.day)
          : null;

      if (lastActiveDay == today) {
        // Already recorded today
        result = StreakUpdateResult(
          streakUpdated: false,
          newStreak: profile['streak'] ?? 0,
          isNewRecord: false,
          milestoneReached: null,
        );
        return;
      }

      int currentStreak = profile['streak'] ?? 0;
      int longestStreak = profile['longestStreak'] ?? 0;
      bool hasGraceDay = profile['hasGraceDayAvailable'] ?? true;

      // Calendar-date math (NOT Duration subtraction) so DST transitions
      // don't shift these off midnight and break the equality comparison.
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final twoDaysAgo = DateTime(today.year, today.month, today.day - 2);

      bool streakBroken = false;

      if (lastActiveDay == null) {
        // First ever activity
        currentStreak = 1;
      } else if (lastActiveDay == yesterday) {
        // Consecutive day — extend streak
        currentStreak++;
      } else if (lastActiveDay == twoDaysAgo && hasGraceDay) {
        // Missed one day — use grace day
        currentStreak++;
        hasGraceDay = false;
      } else {
        // Streak broken (or gap > 2 days without grace)
        streakBroken = true;
        currentStreak = 1;
      }

      if (currentStreak > longestStreak) {
        longestStreak = currentStreak;
      }

      final milestones = [3, 7, 14, 30, 60, 100, 365];
      final int? milestone = milestones.contains(currentStreak) ? currentStreak : null;

      tx.update(ref, {
        'profile.streak': currentStreak,
        'profile.longestStreak': longestStreak,
        'profile.lastActiveDate': Timestamp.fromDate(today),
        'profile.hasGraceDayAvailable': hasGraceDay,
        'profile.totalStudyDays': FieldValue.increment(1),
      });

      result = StreakUpdateResult(
        streakUpdated: true,
        newStreak: currentStreak,
        isNewRecord: currentStreak == longestStreak && currentStreak > 1,
        milestoneReached: milestone,
        streakBroken: streakBroken,
      );
    });

    // Replenish grace day every Monday
    final now = DateTime.now();
    if (now.weekday == DateTime.monday) {
      await ref.update({'profile.hasGraceDayAvailable': true});
    }

    return result;
  }

  Future<bool> useStreakFreeze(String uid) async {
    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();
    final profile = (snap.data() as Map<String, dynamic>)['profile'] as Map<String, dynamic>;

    final freezeCount = profile['streakFreezeCount'] ?? 0;
    if (freezeCount <= 0) return false;

    await ref.update({
      'profile.streakFreezeCount': FieldValue.increment(-1),
      'profile.lastActiveDate': Timestamp.fromDate(DateTime.now()),
    });

    return true;
  }
}

class StreakUpdateResult {
  final bool streakUpdated;
  final int newStreak;
  final bool isNewRecord;
  final int? milestoneReached;
  final bool streakBroken;

  const StreakUpdateResult({
    required this.streakUpdated,
    required this.newStreak,
    required this.isNewRecord,
    this.milestoneReached,
    this.streakBroken = false,
  });
}
