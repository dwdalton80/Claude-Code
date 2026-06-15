import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupRole { creator, member }
enum FeedItemType { sharedNote, badgeEarned, sharedQuestion, streakMilestone, memoryVerseMastered }

class Group {
  final String id;
  final String name;
  final String topic;
  final String? description;
  final DateTime? endDate;
  final String creatorUid;
  final DateTime createdAt;
  final String inviteCode;
  final int memberCount;
  final DateTime? lastActivity;
  final String? coverImageUrl;

  const Group({
    required this.id,
    required this.name,
    required this.topic,
    this.description,
    this.endDate,
    required this.creatorUid,
    required this.createdAt,
    required this.inviteCode,
    required this.memberCount,
    this.lastActivity,
    this.coverImageUrl,
  });

  factory Group.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Group(
      id: doc.id,
      name: data['displayName'] ?? data['name'] ?? 'Member',
      topic: data['topic'] ?? '',
      description: data['description'],
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      creatorUid: data['creatorUid'] ?? data['creatorId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      inviteCode: data['inviteCode'] ?? '',
      memberCount: data['memberCount'] ?? 0,
      lastActivity: (data['lastActivity'] as Timestamp?)?.toDate(),
      coverImageUrl: data['coverImageUrl'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'topic': topic,
        'description': description,
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'creatorUid': creatorUid,
        'createdAt': Timestamp.fromDate(createdAt),
        'inviteCode': inviteCode,
        'memberCount': memberCount,
        'lastActivity': lastActivity != null ? Timestamp.fromDate(lastActivity!) : null,
        'coverImageUrl': coverImageUrl,
      };
}

class GroupMember {
  final String uid;
  final String name;
  final String? avatarUrl;
  final GroupRole role;
  final DateTime joinedAt;
  final AutoPostSettings autoPostSettings;
  final bool mutedNotifications;
  final int weeklyXp;
  final int streak;
  final int badgeCount;
  final int versesMemorized;

  const GroupMember({
    required this.uid,
    required this.name,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
    required this.autoPostSettings,
    required this.mutedNotifications,
    required this.weeklyXp,
    required this.streak,
    required this.badgeCount,
    required this.versesMemorized,
  });

  factory GroupMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupMember(
      uid: doc.id,
      name: data['displayName'] ?? data['name'] ?? 'Member',
      avatarUrl: data['avatarUrl'],
      role: GroupRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => GroupRole.member,
      ),
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      autoPostSettings: AutoPostSettings.fromMap(
        data['autoPostSettings'] as Map<String, dynamic>? ?? {},
      ),
      mutedNotifications: data['mutedNotifications'] ?? false,
      weeklyXp: data['weeklyXp'] ?? 0,
      streak: data['currentStreak'] ?? data['streak'] ?? 0,
      badgeCount: data['badgeCount'] ?? 0,
      versesMemorized: data['versesMemorized'] ?? 0,
    );
  }
}

class AutoPostSettings {
  final bool badges;
  final bool streaks;
  final bool memoryVerses;

  const AutoPostSettings({
    required this.badges,
    required this.streaks,
    required this.memoryVerses,
  });

  factory AutoPostSettings.defaults() => const AutoPostSettings(
        badges: true,
        streaks: true,
        memoryVerses: true,
      );

  factory AutoPostSettings.fromMap(Map<String, dynamic> data) => AutoPostSettings(
        badges: data['badges'] ?? true,
        streaks: data['streaks'] ?? true,
        memoryVerses: data['memoryVerses'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'badges': badges,
        'streaks': streaks,
        'memoryVerses': memoryVerses,
      };
}

class FeedItem {
  final String id;
  final FeedItemType type;
  final String authorUid;
  final String authorName;
  final String? authorAvatar;
  final Map<String, dynamic> content;
  final DateTime timestamp;
  final int reactionCount;
  final int commentCount;

  const FeedItem({
    required this.id,
    required this.type,
    required this.authorUid,
    required this.authorName,
    this.authorAvatar,
    required this.content,
    required this.timestamp,
    required this.reactionCount,
    required this.commentCount,
  });

  factory FeedItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedItem(
      id: doc.id,
      type: FeedItemType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => FeedItemType.sharedNote,
      ),
      authorUid: data['authorUid'] ?? '',
      authorName: data['authorName'] ?? '',
      authorAvatar: data['authorAvatar'],
      content: data['content'] is Map ? Map<String, dynamic>.from(data['content']) : {'text': data['content']?.toString() ?? ''},
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      reactionCount: data['reactionCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type.name,
        'authorUid': authorUid,
        'authorName': authorName,
        'authorAvatar': authorAvatar,
        'content': content,
        'timestamp': Timestamp.fromDate(timestamp),
        'reactionCount': reactionCount,
        'commentCount': commentCount,
      };
}

class GroupQuestion {
  final String id;
  final String authorUid;
  final String authorName;
  final String question;
  final String? scriptureRef;
  final String? verseText;
  final bool resolved;
  final DateTime timestamp;
  final int commentCount;

  const GroupQuestion({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.question,
    this.scriptureRef,
    this.verseText,
    required this.resolved,
    required this.timestamp,
    required this.commentCount,
  });

  factory GroupQuestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupQuestion(
      id: doc.id,
      authorUid: data['authorUid'] ?? data['authorId'] ?? '',
      authorName: data['authorName'] ?? '',
      question: data['question'] ?? '',
      scriptureRef: data['scriptureRef'] ?? data['verseRef'],
      verseText: data['verseText'],
      resolved: data['resolved'] ?? false,
      timestamp: data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
      commentCount: data['commentCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'authorUid': authorUid,
        'authorName': authorName,
        'question': question,
        'scriptureRef': scriptureRef,
        'verseText': verseText,
        'resolved': resolved,
        'timestamp': Timestamp.fromDate(timestamp),
        'commentCount': commentCount,
      };
}
