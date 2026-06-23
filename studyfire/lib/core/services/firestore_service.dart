import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_profile.dart';
import '../../models/journal_entry.dart';
import '../../models/memory_verse.dart';
import '../../models/group.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  // ── User ─────────────────────────────────────────────────────────────

  Stream<UserProfile?> watchProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots()
        .handleError((_) {}) // swallow permission-denied on sign-out before stream cancels
        .map((snap) {
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

  Future<void> updateDisplayName(String uid, String name) async {
    // Update the user's profile
    await _db.collection('users').doc(uid).update({'profile.name': name});
    // Propagate to all group member docs
    final groupsSnap = await _db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get();
    final batch = _db.batch();
    for (final g in groupsSnap.docs) {
      batch.update(
        g.reference.collection('members').doc(uid),
        {'displayName': name},
      );
    }
    await batch.commit();
    // Keep Firebase Auth display name in sync
    await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
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

  /// Resolves any reference — single verse ("John 3:16") or range ("John 3:22-24").
  /// Returns a combined BibleVerse with concatenated text, or null if not found.
  Future<BibleVerse?> getVerseOrRange(String version, String reference) async {
    final rangeRegex = RegExp(r'^(.+\d+:\d+)-(\d+)$');
    final rangeMatch = rangeRegex.firstMatch(reference.trim());
    if (rangeMatch != null) {
      // It's a range like "John 3:22-24"
      final startRef = rangeMatch.group(1)!.trim();
      final endVerseNum = int.tryParse(rangeMatch.group(2)!.trim());
      final parts = _parseReference(startRef);
      if (parts == null || endVerseNum == null) return null;
      final startVerseNum = int.parse(parts['verse']!);
      final verses = await getVerses(
        version,
        parts['book']!,
        int.parse(parts['chapter']!),
        startVerse: startVerseNum,
        endVerse: endVerseNum,
      );
      if (verses.isEmpty) return null;
      // Combine into a single pseudo-verse
      final combinedText = verses.map((v) => '${v.verseNum} ${v.text}').join(' ');
      return BibleVerse(
        id: verses.first.id,
        verseNum: verses.first.verseNum,
        text: combinedText,
        reference: reference,
        book: verses.first.book,
        chapter: verses.first.chapter,
      );
    }
    return getVerse(version, reference);
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
    final userDoc = await _db.collection('users').doc(uid).get();
    final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
    final displayName = (profileData['name'] as String?)?.isNotEmpty == true
        ? profileData['name'] as String
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Member';

    final ref = _db.collection('groups').doc();
    await ref.set(group.toFirestore());
    await ref.collection('members').doc(uid).set({
      'joinedAt': FieldValue.serverTimestamp(),
      'role': GroupRole.creator.name,
      'autoPostSettings': settings.toMap(),
      'mutedNotifications': false,
      'displayName': displayName,
      'weeklyXp': 0,
      'streak': 0,
      'badgeCount': 0,
      'versesMemorized': 0,
    });
    return ref.id;
  }

  Future<void> joinGroup(String groupId, String uid, AutoPostSettings settings) async {
    // Read the user's real name from their Firestore profile
    final userDoc = await _db.collection('users').doc(uid).get();
    final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
    final displayName = (profileData['name'] as String?)?.isNotEmpty == true
        ? profileData['name'] as String
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Member';

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
        'displayName': displayName,
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

  // ── Prayer Requests ──────────────────────────────────────────────────────

  Stream<List<PrayerRequest>> watchPrayerRequests(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('prayers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PrayerRequest.fromFirestore).toList());
  }

  Future<void> addPrayerRequest(String groupId, PrayerRequest prayer) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('prayers')
        .doc(prayer.id)
        .set(prayer.toFirestore());
  }

  Future<void> togglePraying(String groupId, String prayerId, String uid, bool currentlyPraying) async {
    final ref = _db.collection('groups').doc(groupId).collection('prayers').doc(prayerId);
    if (currentlyPraying) {
      await ref.update({
        'prayedBy': FieldValue.arrayRemove([uid]),
        'prayedCount': FieldValue.increment(-1),
      });
    } else {
      await ref.update({
        'prayedBy': FieldValue.arrayUnion([uid]),
        'prayedCount': FieldValue.increment(1),
      });
    }
  }

  Future<void> markPrayerAnswered(String groupId, String prayerId) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('prayers')
        .doc(prayerId)
        .update({
          'answered': true,
          'answeredAt': FieldValue.serverTimestamp(),
        });
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
    final userDoc = await _db.collection('users').doc(uid).get();
    final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
    final displayName = (profileData['name'] as String?)?.isNotEmpty == true
        ? profileData['name'] as String
        : FirebaseAuth.instance.currentUser?.displayName ?? 'Member';
    await groupRef.collection('members').doc(uid).set({
      'joinedAt': now,
      'role': GroupRole.creator.name,
      'weeklyXp': 0,
      'streak': 0,
      'badgeCount': 0,
      'versesMemorized': 0,
      'displayName': displayName,
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

  Future<void> updateGroupInfo(
    String groupId, {
    String? name,
    String? topic,
    String? description,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (topic != null) updates['topic'] = topic;
    if (description != null) updates['description'] = description;
    if (updates.isNotEmpty) {
      await _db.collection('groups').doc(groupId).update(updates);
    }
  }

  Future<void> pinAnnouncement(String groupId, String text, String uid) async {
    await _db.collection('groups').doc(groupId).update({
      'pinnedAnnouncement': {
        'text': text,
        'pinnedAt': FieldValue.serverTimestamp(),
        'pinnedByUid': uid,
      },
    });
  }

  Future<void> unpinAnnouncement(String groupId) async {
    await _db.collection('groups').doc(groupId).update({
      'pinnedAnnouncement': FieldValue.delete(),
    });
  }

  Future<void> updateReadingPlan(
    String groupId,
    List<Map<String, dynamic>> plan,
  ) async {
    await _db.collection('groups').doc(groupId).update({'readingPlan': plan});
  }

  Future<void> removeGroupMember(String groupId, String memberUid) async {
    final groupRef = _db.collection('groups').doc(groupId);
    await Future.wait([
      groupRef.collection('members').doc(memberUid).delete(),
      groupRef.update({
        'memberIds': FieldValue.arrayRemove([memberUid]),
        'memberCount': FieldValue.increment(-1),
      }),
    ]);
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

  // Maps common book names/abbreviations → 3-letter Firestore book IDs
  static const _bookIdMap = <String, String>{
    // Old Testament
    'genesis': 'gen', 'gen': 'gen',
    'exodus': 'exo', 'exo': 'exo', 'ex': 'exo',
    'leviticus': 'lev', 'lev': 'lev',
    'numbers': 'num', 'num': 'num',
    'deuteronomy': 'deu', 'deu': 'deu', 'deut': 'deu',
    'joshua': 'jos', 'jos': 'jos', 'josh': 'jos',
    'judges': 'jdg', 'jdg': 'jdg', 'judg': 'jdg',
    'ruth': 'rut', 'rut': 'rut',
    '1 samuel': '1sa', '1sa': '1sa', '1sam': '1sa',
    '2 samuel': '2sa', '2sa': '2sa', '2sam': '2sa',
    '1 kings': '1ki', '1ki': '1ki',
    '2 kings': '2ki', '2ki': '2ki',
    '1 chronicles': '1ch', '1ch': '1ch', '1chr': '1ch',
    '2 chronicles': '2ch', '2ch': '2ch', '2chr': '2ch',
    'ezra': 'ezr', 'ezr': 'ezr',
    'nehemiah': 'neh', 'neh': 'neh',
    'esther': 'est', 'est': 'est',
    'job': 'job',
    'psalms': 'psa', 'psalm': 'psa', 'psa': 'psa', 'ps': 'psa',
    'proverbs': 'pro', 'pro': 'pro', 'prov': 'pro',
    'ecclesiastes': 'ecc', 'ecc': 'ecc', 'eccl': 'ecc',
    'song of solomon': 'sng', 'song of songs': 'sng', 'sng': 'sng', 'sos': 'sng',
    'isaiah': 'isa', 'isa': 'isa',
    'jeremiah': 'jer', 'jer': 'jer',
    'lamentations': 'lam', 'lam': 'lam',
    'ezekiel': 'ezk', 'ezk': 'ezk', 'ezek': 'ezk',
    'daniel': 'dan', 'dan': 'dan',
    'hosea': 'hos', 'hos': 'hos',
    'joel': 'jol', 'jol': 'jol',
    'amos': 'amo', 'amo': 'amo',
    'obadiah': 'oba', 'oba': 'oba',
    'jonah': 'jon', 'jon': 'jon',
    'micah': 'mic', 'mic': 'mic',
    'nahum': 'nam', 'nam': 'nam',
    'habakkuk': 'hab', 'hab': 'hab',
    'zephaniah': 'zep', 'zep': 'zep',
    'haggai': 'hag', 'hag': 'hag',
    'zechariah': 'zec', 'zec': 'zec',
    'malachi': 'mal', 'mal': 'mal',
    // New Testament
    'matthew': 'mat', 'mat': 'mat', 'matt': 'mat',
    'mark': 'mrk', 'mrk': 'mrk',
    'luke': 'luk', 'luk': 'luk',
    'john': 'jhn', 'jhn': 'jhn',
    'acts': 'act', 'act': 'act',
    'romans': 'rom', 'rom': 'rom',
    '1 corinthians': '1co', '1co': '1co', '1cor': '1co',
    '2 corinthians': '2co', '2co': '2co', '2cor': '2co',
    'galatians': 'gal', 'gal': 'gal',
    'ephesians': 'eph', 'eph': 'eph',
    'philippians': 'php', 'php': 'php', 'phil': 'php',
    'colossians': 'col', 'col': 'col',
    '1 thessalonians': '1th', '1th': '1th', '1thess': '1th',
    '2 thessalonians': '2th', '2th': '2th', '2thess': '2th',
    '1 timothy': '1ti', '1ti': '1ti', '1tim': '1ti',
    '2 timothy': '2ti', '2ti': '2ti', '2tim': '2ti',
    'titus': 'tit', 'tit': 'tit',
    'philemon': 'phm', 'phm': 'phm',
    'hebrews': 'heb', 'heb': 'heb',
    'james': 'jas', 'jas': 'jas',
    '1 peter': '1pe', '1pe': '1pe', '1pet': '1pe',
    '2 peter': '2pe', '2pe': '2pe', '2pet': '2pe',
    '1 john': '1jn', '1jn': '1jn',
    '2 john': '2jn', '2jn': '2jn',
    '3 john': '3jn', '3jn': '3jn',
    'jude': 'jud', 'jud': 'jud',
    'revelation': 'rev', 'rev': 'rev',
  };

  Map<String, String>? _parseReference(String ref) {
    // Handles "John 3:16", "Psalm 23:1", "1 Corinthians 13:4"
    // Non-greedy book match stops before the chapter number.
    final regex = RegExp(r'^(\d\s)?([A-Za-z][A-Za-z\s]*?)\s+(\d+):(\d+)$');
    final match = regex.firstMatch(ref.trim());
    if (match == null) return null;
    // Reconstruct book: optional leading digit + space + book name
    final prefix = match.group(1) ?? '';          // e.g. "1 "
    final name   = match.group(2)!.trim();        // e.g. "Corinthians"
    final rawBook = (prefix + name).trim().toLowerCase();
    final bookId = _bookIdMap[rawBook];
    if (bookId == null) return null;
    return {
      'book': bookId,
      'chapter': match.group(3)!,
      'verse': match.group(4)!,
    };
  }

  // Post activity to all groups the user belongs to
  Future<void> postActivityToUserGroups(String uid, String authorName, FeedItemType type, Map<String, dynamic> content) async {
    try {
      final groupsSnap = await _db
          .collection('groups')
          .where('memberIds', arrayContains: uid)
          .get();
      for (final doc in groupsSnap.docs) {
        await _db.collection('groups').doc(doc.id).collection('feed').add({
          'authorUid': uid,
          'authorName': authorName,
          'type': type.name,
          'content': content,
          'timestamp': FieldValue.serverTimestamp(),
        });
        await _db.collection('groups').doc(doc.id).update({
          'lastActivity': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
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

  // Post activity to all groups the user belongs to
}
