import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';
import '../../models/journal_entry.dart';
import '../../models/memory_verse.dart';
import '../../models/group.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ── User ─────────────────────────────────────────────────────────────

  Stream<UserProfile?> watchProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data()!;
      final profileData = data['profile'] as Map<String, dynamic>? ?? {};
      return UserProfile.fromFirestore(
        // Wrap profile sub-document as a fake DocumentSnapshot
        _FakeDoc(uid, profileData),
      );
    });
  }

  Future<UserProfile?> getProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data()!;
    final profileData = data['profile'] as Map<String, dynamic>? ?? {};
    return UserProfile.fromFirestore(_FakeDoc(uid, profileData));
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> updates) async {
    final prefixed = updates.map((k, v) => MapEntry('profile.$k', v));
    await _db.collection('users').doc(uid).update(prefixed);
  }

  Future<void> updatePreferences(
    String uid, {
    BibleVersion? version,
    SessionLength? sessionLength,
    StudyLevel? studyLevel,
    StudyGoal? goal,
  }) async {
    final updates = <String, dynamic>{};
    if (version != null) updates['profile.defaultVersion'] = version.name;
    if (sessionLength != null) updates['profile.sessionLength'] = sessionLength.name;
    if (studyLevel != null) updates['profile.studyLevel'] = studyLevel.name;
    if (goal != null) updates['profile.goal'] = goal.name;
    if (updates.isNotEmpty) {
      await _db.collection('users').doc(uid).update(updates);
    }
  }

  Future<void> updateTopicTags(String uid, List<String> tags) async {
    await _db.collection('users').doc(uid).update({'topicTags.selected': tags});
  }

  Future<void> updateTopicMastery(String uid, String tag, String level) async {
    await _db.collection('users').doc(uid).update({'topicTags.mastery.$tag': level});
  }

  // ── Bible ─────────────────────────────────────────────────────────────

  Future<List<BibleVerse>> getVerses(
    String version,
    String book,
    int chapter, {
    int? startVerse,
    int? endVerse,
  }) async {
    Query query = _db
        .collection('bible')
        .doc(version)
        .collection('books')
        .doc(book)
        .collection('chapters')
        .doc(chapter.toString())
        .collection('verses')
        .orderBy('verseNumber');

    if (startVerse != null) query = query.where('verseNumber', isGreaterThanOrEqualTo: startVerse);
    if (endVerse != null) query = query.where('verseNumber', isLessThanOrEqualTo: endVerse);

    final snap = await query.get();
    return snap.docs.map((d) => BibleVerse.fromFirestore(d)).toList();
  }

  Future<BibleVerse?> getVerse(String version, String reference) async {
    // reference format: "John 3:16"
    final parts = _parseReference(reference);
    if (parts == null) return null;

    final snap = await _db
        .collection('bible')
        .doc(version)
        .collection('books')
        .doc(parts['book']!)
        .collection('chapters')
        .doc(parts['chapter']!)
        .collection('verses')
        .where('verseNumber', isEqualTo: int.parse(parts['verse']!))
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return BibleVerse.fromFirestore(snap.docs.first);
  }

  // ── Spark Cache ────────────────────────────────────────────────────────

  Future<SparkQuestion?> getTodaySparkQuestion(String passageId, String version) async {
    final today = _dateKey(DateTime.now());
    final snap = await _db
        .collection('sparkcache')
        .doc(today)
        .collection(passageId)
        .doc(version)
        .get();

    if (!snap.exists) return null;
    final data = snap.data()!;
    return SparkQuestion(
      question: data['question'] ?? '',
      verseText: data['verseText'] ?? '',
      reference: data['reference'] ?? '',
    );
  }

  // ── Daily Cache (Quiz, Word of Day) ────────────────────────────────────

  Future<Map<String, dynamic>?> getDailyCache() async {
    final today = _dateKey(DateTime.now());
    final snap = await _db.collection('dailycache').doc(today).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  // ── Highlights ──────────────────────────────────────────────────────────

  Future<void> clearHighlight({required String uid, required String verseId}) async {
    await _db
        .collection('highlights')
        .doc(uid)
        .collection('verses')
        .doc(verseId)
        .delete();
  }

  Future<void> saveHighlight({
    required String uid,
    required String verseId,
    required String color,
    String? note,
  }) async {
    await _db
        .collection('highlights')
        .doc(uid)
        .collection('verses')
        .doc(verseId)
        .set({
      'color': color,
      'note': note,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveNote({
    required String uid,
    required String verseId,
    required String note,
    required String reference,
  }) async {
    await _db
        .collection('notes')
        .doc(uid)
        .collection('verses')
        .doc(verseId)
        .set({
      'note': note,
      'reference': reference,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, String>> loadNotes(String uid) async {
    final snap = await _db
        .collection('notes')
        .doc(uid)
        .collection('verses')
        .get();
    return Map.fromEntries(
      snap.docs.map((d) => MapEntry(d.id, d.data()['note'] as String? ?? '')),
    );
  }

  Future<void> removeHighlight(String uid, String verseId) async {
    await _db.collection('highlights').doc(uid).collection('verses').doc(verseId).delete();
  }

  Stream<QuerySnapshot> watchHighlights(String uid) {
    return _db.collection('highlights').doc(uid).collection('verses').snapshots();
  }

  // ── Journal ─────────────────────────────────────────────────────────────

  Stream<List<JournalEntry>> watchJournal(String uid) {
    return _db
        .collection('journal')
        .doc(uid)
        .collection('entries')
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(JournalEntry.fromFirestore).toList());
  }

  Future<void> deleteJournalEntry(String uid, String entryId) async {
    await _db
        .collection('journal')
        .doc(uid)
        .collection('entries')
        .doc(entryId)
        .delete();
  }

  Future<List<JournalEntry>> getJournalEntries(String uid) async {
    final snap = await _db
        .collection('journal')
        .doc(uid)
        .collection('entries')
        .orderBy('updatedAt', descending: true)
        .get();
    return snap.docs.map((d) => JournalEntry.fromFirestore(d)).toList();
  }

  Future<String> saveJournalEntry(String uid, JournalEntry entry) async {
    final ref = entry.id.isEmpty
        ? _db.collection('journal').doc(uid).collection('entries').doc()
        : _db.collection('journal').doc(uid).collection('entries').doc(entry.id);
    await ref.set(entry.toFirestore());
    return ref.id;
  }

  Future<void> updateApplicationPoint(
    String uid,
    String entryId,
    String pointId,
    bool done,
  ) async {
    final snap = await _db
        .collection('journal')
        .doc(uid)
        .collection('entries')
        .doc(entryId)
        .get();

    if (!snap.exists) return;
    final data = snap.data()!;
    final points = List<Map<String, dynamic>>.from(
      data['aiApplicationPoints'] as List? ?? [],
    );

    final idx = points.indexWhere((p) => p['id'] == pointId);
    if (idx == -1) return;

    points[idx]['done'] = done;
    points[idx]['doneAt'] = done ? Timestamp.now() : null;

    await snap.reference.update({'aiApplicationPoints': points});
  }

  // ── Memory Verses ────────────────────────────────────────────────────────

  Stream<List<MemoryVerse>> watchMemoryVerses(String uid) {
    return _db
        .collection('memoryVerses')
        .doc(uid)
        .collection('verses')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(MemoryVerse.fromFirestore).toList());
  }

 Future<List<MemoryVerse>> getVersesDueForReview(String uid) async {
    final snap = await _db
        .collection('memoryVerses')
        .doc(uid)
        .collection('verses')
        .where('mastered', isEqualTo: false)
        .where('nextReviewDate', isLessThanOrEqualTo: Timestamp.now())
        .get();
    return snap.docs.map(MemoryVerse.fromFirestore).toList();
  }
  Future<void> saveMemoryVerse(String uid, MemoryVerse verse) async {
    await _db
        .collection('memoryVerses')
        .doc(uid)
        .collection('verses')
        .doc(verse.id)
        .set(verse.toFirestore());
  }

  // ── Groups ───────────────────────────────────────────────────────────────

  Stream<List<Group>> watchMyGroups(String uid) {
    return _db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.exists)
            .map(Group.fromFirestore)
            .toList());
  }

  Future<Group?> getGroupByInviteCode(String code) async {
    final snap = await _db
        .collection('groups')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Group.fromFirestore(snap.docs.first);
  }

  Future<String> createGroup(Group group, String uid, AutoPostSettings settings) async {
    final ref = _db.collection('groups').doc();
    await ref.set(group.toFirestore());
    await ref.collection('members').doc(uid).set({
      'joinedAt': FieldValue.serverTimestamp(),
      'role': GroupRole.creator.name,
      'autoPostSettings': settings.toMap(),
      'mutedNotifications': false,
      'weeklyXp': 0,
      'streak': 0,
      'badgeCount': 0,
      'versesMemorized': 0,
    });
    return ref.id;
  }

  Future<void> joinGroup(String groupId, String uid, AutoPostSettings settings) async {
    final groupRef = _db.collection('groups').doc(groupId);
    await _db.runTransaction((tx) async {
      tx.set(groupRef.collection('members').doc(uid), {
        'joinedAt': FieldValue.serverTimestamp(),
        'role': GroupRole.member.name,
        'autoPostSettings': settings.toMap(),
        'mutedNotifications': false,
        'weeklyXp': 0,
        'streak': 0,
        'badgeCount': 0,
        'versesMemorized': 0,
      });
      tx.update(groupRef, {'memberCount': FieldValue.increment(1)});
    });
  }

  Stream<List<FeedItem>> watchGroupFeed(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('feed')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(FeedItem.fromFirestore).toList());
  }

  Future<void> postToGroupFeed(String groupId, FeedItem item) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('feed')
        .add(item.toFirestore());
    await _db.collection('groups').doc(groupId).update({
      'lastActivity': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<GroupQuestion>> watchGroupQuestions(String groupId) {
    return _db
        .collection('groupQuestions')
        .doc(groupId)
        .collection('questions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((s) => s.docs.map(GroupQuestion.fromFirestore).toList());
  }

  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final snap = await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();
    return snap.docs.map(GroupMember.fromFirestore).toList();
  }

  // Convenience: create group with just a name
  Future<String> createGroupSimple(String uid, String name) async {
    final inviteCode = _generateCode();
    final groupRef = _db.collection('groups').doc();
    final now = FieldValue.serverTimestamp();
    await groupRef.set({
      'name': name,
      'creatorId': uid,
      'inviteCode': inviteCode,
      'memberCount': 1,
      'memberIds': [uid],
      'createdAt': now,
      'lastActivity': now,
      'autoPostSettings': AutoPostSettings.defaults().toMap(),
    });
    await groupRef.collection('members').doc(uid).set({
      'joinedAt': now,
      'role': GroupRole.creator.name,
      'weeklyXp': 0,
      'currentStreak': 0,
      'badgeCount': 0,
      'versesMemorized': 0,
      'displayName': '',
    });
    return groupRef.id;
  }

  // Convenience: join group by invite code
  Future<void> joinGroupByCode(String uid, String inviteCode) async {
    final group = await getGroupByInviteCode(inviteCode.toUpperCase());
    if (group == null) throw Exception('Invalid invite code');
    await joinGroup(group.id, uid, AutoPostSettings.defaults());
    await _db.collection('groups').doc(group.id).update({
      'memberIds': FieldValue.arrayUnion([uid]),
    });
  }

  // Convenience: post a typed message to group feed
  Future<void> postFeedMessage(
    String groupId,
    String uid,
    String authorName,
    FeedItemType type,
    String content,
  ) async {
    await _db.collection('groups').doc(groupId).collection('feed').add({
      'type': type.name,
      'authorId': uid,
      'authorName': authorName,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
      'comments': [],
      'reactions': [],
    });
    await _db.collection('groups').doc(groupId).update({
      'lastActivity': FieldValue.serverTimestamp(),
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buf = StringBuffer();
    final rand = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 6; i++) {
      buf.write(chars[(rand >> (i * 5)) % chars.length]);
    }
    return buf.toString();
  }

  // ── Auto-bookmark ──────────────────────────────────────────────────────────

  Future<void> saveReadingPosition(
    String uid,
    String version,
    String book,
    int chapter,
    int verse,
  ) async {
    await _db.collection('users').doc(uid).update({
      'readingPosition': {
        'version': version,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'savedAt': FieldValue.serverTimestamp(),
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Map<String, String>? _parseReference(String ref) {
    // Handles "John 3:16", "1 Corinthians 13:4"
    final regex = RegExp(r'^(\d?\s?[A-Za-z]+)\s+(\d+):(\d+)$');
    final match = regex.firstMatch(ref.trim());
    if (match == null) return null;
    return {
      'book': match.group(1)!.trim().toLowerCase().replaceAll(' ', '_'),
      'chapter': match.group(2)!,
      'verse': match.group(3)!,
    };
  }
}

// Lightweight wrapper so model fromFirestore() constructors can work on sub-documents
class _FakeDoc implements DocumentSnapshot {
  final String _id;
  final Map<String, dynamic> _data;

  _FakeDoc(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  bool get exists => true;

  // Unused interface members
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BibleVerse {
  final String id;
  final String reference;
  final String text;
  final int verseNum;
  final String book;
  final int chapter;

  const BibleVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.verseNum,
    required this.book,
    required this.chapter,
  });

  factory BibleVerse.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BibleVerse(
      id: doc.id,
      reference: data['reference'] ?? '',
      text: data['text'] ?? '',
      verseNum: data['verseNumber'] ?? 0,
      book: data['bookId'] ?? '',
      chapter: data['chapterNumber'] ?? 0,
    );
  }
}

class SparkQuestion {
  final String question;
  final String verseText;
  final String reference;

  const SparkQuestion({
    required this.question,
    required this.verseText,
    required this.reference,
  });
}
