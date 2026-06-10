import * as admin from "firebase-admin";

const db = () => admin.firestore();

export interface StreakStatus {
  currentStreak: number;
  longestStreak: number;
  hasGraceDayAvailable: boolean;
  lastActiveDate: Date | null;
  streakFreezeCount: number;
}

export interface StreakUpdateResult {
  newStreak: number;
  wasExtended: boolean;
  usedGraceDay: boolean;
  streakBroken: boolean;
  isNewRecord: boolean;
  milestoneReached: number | null;
}

/**
 * Records a study activity for the user and updates streak.
 * Designed to be called from session-end Cloud Function trigger.
 */
export async function recordStudyActivity(uid: string): Promise<StreakUpdateResult> {
  const ref = db().collection("users").doc(uid);

  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error(`User ${uid} not found`);

    const data = snap.data()!;
    const profile = data.profile as Record<string, unknown>;

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const lastActiveTstamp = profile.lastActiveDate as admin.firestore.Timestamp | null;
    const lastActive = lastActiveTstamp?.toDate() ?? null;
    const lastActiveDay = lastActive
      ? new Date(lastActive.getFullYear(), lastActive.getMonth(), lastActive.getDate())
      : null;

    // Already recorded today
    if (lastActiveDay && lastActiveDay.getTime() === today.getTime()) {
      return {
        newStreak: (profile.streak as number) ?? 0,
        wasExtended: false,
        usedGraceDay: false,
        streakBroken: false,
        isNewRecord: false,
        milestoneReached: null,
      };
    }

    let streak = (profile.streak as number) ?? 0;
    let longestStreak = (profile.longestStreak as number) ?? 0;
    let hasGraceDay = (profile.hasGraceDayAvailable as boolean) ?? true;
    let usedGraceDay = false;
    let streakBroken = false;

    const yesterday = new Date(today);
    yesterday.setDate(today.getDate() - 1);
    const twoDaysAgo = new Date(today);
    twoDaysAgo.setDate(today.getDate() - 2);

    if (!lastActiveDay) {
      streak = 1;
    } else if (lastActiveDay.getTime() === yesterday.getTime()) {
      streak++;
    } else if (lastActiveDay.getTime() === twoDaysAgo.getTime() && hasGraceDay) {
      streak++;
      hasGraceDay = false;
      usedGraceDay = true;
    } else {
      streakBroken = true;
      streak = 1;
    }

    if (streak > longestStreak) longestStreak = streak;

    const milestones = [3, 7, 14, 30, 60, 100, 365];
    const milestoneReached = milestones.includes(streak) ? streak : null;

    tx.update(ref, {
      "profile.streak": streak,
      "profile.longestStreak": longestStreak,
      "profile.lastActiveDate": admin.firestore.Timestamp.fromDate(today),
      "profile.hasGraceDayAvailable": hasGraceDay,
      "profile.totalStudyDays": admin.firestore.FieldValue.increment(1),
    });

    return {
      newStreak: streak,
      wasExtended: !streakBroken,
      usedGraceDay,
      streakBroken,
      isNewRecord: streak === longestStreak && streak > 1,
      milestoneReached,
    };
  });
}

/**
 * Called weekly (Monday) to replenish the grace day token.
 */
export async function replenishGraceDays(): Promise<void> {
  const snapshot = await db().collection("users").get();
  const batch = db().batch();

  for (const doc of snapshot.docs) {
    batch.update(doc.ref, { "profile.hasGraceDayAvailable": true });
  }

  await batch.commit();
}
