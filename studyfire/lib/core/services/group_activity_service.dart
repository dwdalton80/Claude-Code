import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';

class GroupActivityService {
  final _db = FirebaseFirestore.instance;

  Future<void> updateMemberWeeklyXp(String uid, int xp) async {
    try {
      // Read name and streak from Firestore profile (source of truth)
      final userDoc = await _db.collection('users').doc(uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final profile = userData['profile'] as Map<String, dynamic>? ?? {};
      final firestoreName = (profile['name'] as String?)?.isNotEmpty == true
          ? profile['name'] as String
          : null;
      final authUser = FirebaseAuth.instance.currentUser;
      final displayName = firestoreName ??
          authUser?.displayName ??
          authUser?.email?.split('@')[0] ??
          'Member';
      final streak = (profile['streak'] as num?)?.toInt() ?? 0;
      final groupsSnap = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
      for (final doc in groupsSnap.docs) {
        await _db.collection('groups').doc(doc.id).collection('members').doc(uid).set({
          'weeklyXp': FieldValue.increment(xp),
          'displayName': displayName,
          'currentStreak': streak,
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> postActivityToUserGroups(String uid, String authorName, FeedItemType type, Map<String, dynamic> content) async {
    try {
      // Prefer Firestore profile name — Firebase Auth displayName is often null
      String resolvedName = authorName;
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        final data = userDoc.data() as Map<String, dynamic>? ?? {};
        final profile = data['profile'] as Map<String, dynamic>? ?? {};
        final firestoreName = (profile['name'] as String?)?.isNotEmpty == true
            ? profile['name'] as String
            : null;
        if (firestoreName != null) resolvedName = firestoreName;
      } catch (_) {}

      final groupsSnap = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
      for (final doc in groupsSnap.docs) {
        await _db.collection('groups').doc(doc.id).collection('feed').add({
          'authorUid': uid,
          'authorName': resolvedName,
          'type': type.name,
          'content': content,
          'timestamp': FieldValue.serverTimestamp(),
        });
        await _db.collection('groups').doc(doc.id).update({'lastActivity': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }
}
