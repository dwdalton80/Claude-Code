import 'package:cloud_firestore/cloud_firestore.dart';

enum MemoryVerseStage { stage1, stage2, stage3, stage4, stage5 }

class MemoryVerse {
  final String id;
  final String reference;
  final String text;
  final MemoryVerseStage currentStage;
  final bool mastered;
  final DateTime? lastReviewed;
  final DateTime? nextReviewDate;
  final List<VerseAttempt> attemptHistory;
  final int easeFactor; // SM-2: starts at 2.5 * 100 to avoid floats
  final int interval;   // days until next review
  final int repetitions;

  const MemoryVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.currentStage,
    required this.mastered,
    this.lastReviewed,
    this.nextReviewDate,
    required this.attemptHistory,
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
  });

  factory MemoryVerse.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MemoryVerse(
      id: doc.id,
      reference: data['reference'] ?? '',
      text: data['text'] ?? '',
      currentStage: MemoryVerseStage.values.firstWhere(
        (e) => e.name == data['currentStage'],
        orElse: () => MemoryVerseStage.stage1,
      ),
      mastered: data['mastered'] ?? false,
      lastReviewed: (data['lastReviewed'] as Timestamp?)?.toDate(),
      nextReviewDate: (data['nextReviewDate'] as Timestamp?)?.toDate(),
      attemptHistory: (data['attemptHistory'] as List<dynamic>? ?? [])
          .map((e) => VerseAttempt.fromMap(e as Map<String, dynamic>))
          .toList(),
      easeFactor: data['easeFactor'] ?? 250,
      interval: data['interval'] ?? 1,
      repetitions: data['repetitions'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'reference': reference,
        'text': text,
        'currentStage': currentStage.name,
        'mastered': mastered,
        'lastReviewed': lastReviewed != null ? Timestamp.fromDate(lastReviewed!) : null,
        'nextReviewDate': nextReviewDate != null ? Timestamp.fromDate(nextReviewDate!) : null,
        'attemptHistory': attemptHistory.map((e) => e.toMap()).toList(),
        'easeFactor': easeFactor,
        'interval': interval,
        'repetitions': repetitions,
      };

  MemoryVerse copyWith({
    MemoryVerseStage? currentStage,
    bool? mastered,
    DateTime? lastReviewed,
    DateTime? nextReviewDate,
    List<VerseAttempt>? attemptHistory,
    int? easeFactor,
    int? interval,
    int? repetitions,
  }) {
    return MemoryVerse(
      id: id,
      reference: reference,
      text: text,
      currentStage: currentStage ?? this.currentStage,
      mastered: mastered ?? this.mastered,
      lastReviewed: lastReviewed ?? this.lastReviewed,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      attemptHistory: attemptHistory ?? this.attemptHistory,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
    );
  }
}

class VerseAttempt {
  final DateTime date;
  final MemoryVerseStage stage;
  final double score; // 0.0 to 1.0
  final bool passed;

  const VerseAttempt({
    required this.date,
    required this.stage,
    required this.score,
    required this.passed,
  });

  factory VerseAttempt.fromMap(Map<String, dynamic> data) => VerseAttempt(
        date: (data['date'] as Timestamp).toDate(),
        stage: MemoryVerseStage.values.firstWhere(
          (e) => e.name == data['stage'],
          orElse: () => MemoryVerseStage.stage1,
        ),
        score: (data['score'] as num).toDouble(),
        passed: data['passed'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'stage': stage.name,
        'score': score,
        'passed': passed,
      };
}
