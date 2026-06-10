/**
 * SM-2 Spaced Repetition Algorithm
 * Classic implementation as described by Piotr Wozniak.
 *
 * Quality grades (0–5):
 *   5 = perfect response
 *   4 = correct with slight hesitation
 *   3 = correct with difficulty
 *   2 = incorrect — easy to recall after seeing the answer
 *   1 = incorrect — hard to recall even after seeing
 *   0 = complete blackout
 */

export interface SM2Card {
  easeFactor: number; // stored as integer * 100 (e.g. 250 = 2.5)
  interval: number;   // days until next review
  repetitions: number;
}

export interface SM2Result extends SM2Card {
  nextReviewDate: Date;
  passed: boolean;
}

export function sm2Update(card: SM2Card, qualityGrade: number): SM2Result {
  // Clamp grade to 0-5
  const q = Math.max(0, Math.min(5, qualityGrade));
  const passed = q >= 3;

  let { easeFactor, interval, repetitions } = card;

  if (passed) {
    if (repetitions === 0) {
      interval = 1;
    } else if (repetitions === 1) {
      interval = 6;
    } else {
      interval = Math.round(interval * (easeFactor / 100));
    }
    repetitions++;
  } else {
    // Failed — reset to beginning
    repetitions = 0;
    interval = 1;
  }

  // Update ease factor: EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
  // Using integer math (factor * 100)
  const efDelta = Math.round(
    (10 - (5 - q) * (8 + (5 - q) * 2))
  ); // * 100 scale: 0.1 -> 10, etc.
  easeFactor = Math.max(130, easeFactor + efDelta); // minimum EF = 1.3

  const nextReviewDate = new Date();
  nextReviewDate.setDate(nextReviewDate.getDate() + interval);

  return { easeFactor, interval, repetitions, nextReviewDate, passed };
}

/**
 * Maps a stage-5 score (percentage correct) to SM-2 quality grade.
 * 100% = 5, 95% = 4, 90% = 3 (pass threshold), < 90% = fail
 */
export function scoreToGrade(percentCorrect: number): number {
  if (percentCorrect >= 1.0) return 5;
  if (percentCorrect >= 0.95) return 4;
  if (percentCorrect >= 0.9) return 3;
  if (percentCorrect >= 0.7) return 2;
  if (percentCorrect >= 0.5) return 1;
  return 0;
}

/**
 * Returns how many days until a card is due for review.
 * Negative = overdue.
 */
export function daysUntilReview(nextReviewDate: Date): number {
  const now = new Date();
  const diff = nextReviewDate.getTime() - now.getTime();
  return Math.ceil(diff / (1000 * 60 * 60 * 24));
}
