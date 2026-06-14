import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group.dart';

class GroupActivityService {
  final _db = FirebaseFirestore.instance;

  Future<void> updateMemberWeeklyXp(String uid, int xp) async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      final displayName = authUser?.displayName ?? authUser?.email?.split('@')[0] ?? 'Member';
      final groupsSnap = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
      for (final doc in groupsSnap.docs) {
        await _db.collection('groups').doc(doc.id).collection('members').doc(uid).set({
          'weeklyXp': FieldValue.increment(xp),
          'displayName': displayName,
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> postActivityToUserGroups(String uid, String authorName, FeedItemType type, Map<String, dynamic> content) async {
    try {
      final groupsSnap = await _db.collection('groups').where('memberIds', arrayContains: uid).get();
      for (final doc in groupsSnap.docs) {
        await _db.collection('groups').doc(doc.id).collection('feed').add({
          'authorUid': uid,
          'authorName': authorName,
          'type': type.name,
          'content': content,
          'timestamp': FieldValue.serverTimestamp(),
        });
        await _db.collection('groups').doc(doc.id).update({'lastActivity': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }
}
