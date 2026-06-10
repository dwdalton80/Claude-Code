import 'package:cloud_firestore/cloud_firestore.dart';

enum JournalType { sermon, personalStudy, readingPlan }

class JournalEntry {
  final String id;
  final JournalType type;
  final String title;
  final DateTime date;
  final String? speaker;
  final String? passage;
  final String content;
  final List<String> scriptureRefs;
  final List<ApplicationPoint> aiApplicationPoints;
  final List<String> aiDiscussionQuestions;
  final String? aiBigIdea;
  final String? aiPersonalChallenge;
  final bool aiDebriefGenerated;
  final int aiDebriefUsedThisMonth;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    this.speaker,
    this.passage,
    required this.content,
    required this.scriptureRefs,
    required this.aiApplicationPoints,
    required this.aiDiscussionQuestions,
    this.aiBigIdea,
    this.aiPersonalChallenge,
    required this.aiDebriefGenerated,
    required this.aiDebriefUsedThisMonth,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JournalEntry(
      id: doc.id,
      type: JournalType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => JournalType.personalStudy,
      ),
      title: data['title'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      speaker: data['speaker'],
      passage: data['passage'],
      content: data['content'] ?? '',
      scriptureRefs: List<String>.from(data['scriptureRefs'] ?? []),
      aiApplicationPoints: (data['aiApplicationPoints'] as List<dynamic>? ?? [])
          .map((e) => ApplicationPoint.fromMap(e as Map<String, dynamic>))
          .toList(),
      aiDiscussionQuestions: List<String>.from(data['aiDiscussionQuestions'] ?? []),
      aiBigIdea: data['aiBigIdea'],
      aiPersonalChallenge: data['aiPersonalChallenge'],
      aiDebriefGenerated: data['aiDebriefGenerated'] ?? false,
      aiDebriefUsedThisMonth: data['aiDebriefUsedThisMonth'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type.name,
        'title': title,
        'date': Timestamp.fromDate(date),
        'speaker': speaker,
        'passage': passage,
        'content': content,
        'scriptureRefs': scriptureRefs,
        'aiApplicationPoints': aiApplicationPoints.map((e) => e.toMap()).toList(),
        'aiDiscussionQuestions': aiDiscussionQuestions,
        'aiBigIdea': aiBigIdea,
        'aiPersonalChallenge': aiPersonalChallenge,
        'aiDebriefGenerated': aiDebriefGenerated,
        'aiDebriefUsedThisMonth': aiDebriefUsedThisMonth,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

class ApplicationPoint {
  final String id;
  final String text;
  final bool done;
  final DateTime? doneAt;

  const ApplicationPoint({
    required this.id,
    required this.text,
    required this.done,
    this.doneAt,
  });

  factory ApplicationPoint.fromMap(Map<String, dynamic> data) => ApplicationPoint(
        id: data['id'] ?? '',
        text: data['text'] ?? '',
        done: data['done'] ?? false,
        doneAt: (data['doneAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'done': done,
        'doneAt': doneAt != null ? Timestamp.fromDate(doneAt!) : null,
      };

  ApplicationPoint copyWith({bool? done, DateTime? doneAt}) => ApplicationPoint(
        id: id,
        text: text,
        done: done ?? this.done,
        doneAt: doneAt ?? this.doneAt,
      );
}
