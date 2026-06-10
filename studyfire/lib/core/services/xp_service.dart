import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';
import '../constants/xp_rewards.dart';

class XpService {
  final _firestore = FirebaseFirestore.instance;

  // Batch accumulates XP changes during a session — flushed on session end
  final Map<String, int> _pendingXp = {};
  int _sessionXp = 0;

  void accumulateXp(String uid, int amount) {
    _pendingXp[uid] = (_pendingXp[uid] ?? 0) + amount;
    _sessionXp += amount;
  }

  int get sessionXp => _sessionXp;

  Future<XpResult> flushSession(String uid) async {
    final pending = _pendingXp.remove(uid) ?? 0;
    _sessionXp = 0;
    if (pending == 0) return XpResult(xpEarned: 0, newBadges: [], leveledUp: false, newLevel: null);

    final ref = _firestore.collection('users').doc(uid);

    late XpResult result;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() as Map<String, dynamic>;
      final profile = data['profile'] as Map<String, dynamic>;
      final currentXp = (profile['xp'] as int?) ?? 0;
      final currentLevel = (profile['level'] as int?) ?? 1;
      final newXp = currentXp + pending;

      final newLevelData = LevelThresholds.forXp(newXp);
      final newLevel = newLevelData['level'] as int;
      final leveledUp = newLevel > currentLevel;

      final newBadges = _checkBadgeMilestones(currentXp, newXp);

      tx.update(ref, {
        'profile.xp': newXp,
        'profile.level': newLevel,
      });

      result = XpResult(
        xpEarned: pending,
        newBadges: newBadges,
        leveledUp: leveledUp,
        newLevel: leveledUp ? newLevelData : null,
      );
    });

    return result;
  }

  List<String> _checkBadgeMilestones(int oldXp, int newXp) {
    final milestones = XpMilestones.badges;
    return milestones.entries
        .where((e) => oldXp < e.key && newXp >= e.key)
        .map((e) => e.value)
        .toList();
  }

  Future<void> awardBadge(String uid, String badgeId) async {
    await _firestore
        .collection('badges')
        .doc(uid)
        .collection('earned')
        .doc(badgeId)
        .set({
      'earnedAt': FieldValue.serverTimestamp(),
      'shared': false,
      'shareCount': 0,
    });
  }

  Future<void> incrementStat(String uid, String stat) async {
    await _firestore.collection('users').doc(uid).update({
      'stats.$stat': FieldValue.increment(1),
    });
  }
}

class XpResult {
  final int xpEarned;
  final List<String> newBadges;
  final bool leveledUp;
  final Map<String, dynamic>? newLevel;

  const XpResult({
    required this.xpEarned,
    required this.newBadges,
    required this.leveledUp,
    this.newLevel,
  });
}
