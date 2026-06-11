import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { generateSparkQuestion } from "./claude/spark_questions";
import { generateAiStudy, StudyContext } from "./claude/ai_study";
import { generateQuizBatch } from "./claude/quiz_generation";
import { generateSermonDebrief, suggestSermonTitle, DebriefContext } from "./claude/sermon_debrief";
import { recordStudyActivity, replenishGraceDays } from "./gamification/streak_manager";
import { sm2Update, scoreToGrade } from "./gamification/sm2_algorithm";
import {
  sendStreakReminders,
  sendFocusCompanion,
  sendGroupDigests,
} from "./notifications/push_notifications";

admin.initializeApp();
const db = admin.firestore();

// ── Scheduled: 2am Daily ─────────────────────────────────────────────────────

/**
 * Pre-generates today's Spark question for each active passage.
 * One Claude call per passage, result shared with ALL free users.
 */
export const generateDailySpark = functions.pubsub.schedule("0 2 * * *").onRun(async () => {
    functions.logger.info("Generating daily spark questions");

    const today = dateKey(new Date());

    // Get today's reading plan passages (simplified: iterate active plans)
    // In production: aggregate from readingPlan documents
    const passages = await getTodaysPassages();

    for (const passage of passages) {
      for (const version of ["kjv", "csb", "niv"]) {
        try {
          const question = await generateSparkQuestion(
            passage.text,
            passage.reference,
            version
          );

          await db
            .collection("sparkcache")
            .doc(today)
            .collection(passage.id)
            .doc(version)
            .set({ ...question, generatedAt: admin.firestore.FieldValue.serverTimestamp() });
        } catch (err) {
          functions.logger.error(`Spark generation failed: ${passage.reference} ${version}`, err);
        }
      }
    }
  });

/**
 * Pre-generates daily quiz questions and Word of the Day via Batch API.
 * 50% cost savings vs individual API calls.
 */
export const generateDailyCache = functions.pubsub.schedule("30 2 * * *").onRun(async () => {
    functions.logger.info("Generating daily cache (quiz + word of day)");

    const today = dateKey(new Date());
    const topicTags = [
      "Anxiety & Fear", "Identity", "Purpose & Calling",
      "Forgiveness", "Prayer", "Relationships",
      "Doubt & Faith", "The Holy Spirit", "Suffering", "Spiritual Growth",
    ];

    try {
      const quizMap = await generateQuizBatch(topicTags);
      const quizData: Record<string, unknown> = {};
      for (const [tag, questions] of quizMap.entries()) {
        quizData[tag] = questions;
      }

      await db.collection("dailycache").doc(today).set(
        { quizQuestions: quizData, generatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    } catch (err) {
      functions.logger.error("Quiz batch generation failed", err);
    }
  });

/**
 * Replenishes grace day tokens every Monday.
 */
export const weeklyGraceReplenish = functions.pubsub.schedule("0 0 * * 1").onRun(async () => {
    functions.logger.info("Replenishing grace day tokens");
    await replenishGraceDays();
  });

// ── Scheduled: Notifications ─────────────────────────────────────────────────

export const sendEveningStreakReminders = functions.pubsub.schedule("0 20 * * *").onRun(async () => {
    functions.logger.info("Sending streak reminders");
    await sendStreakReminders();
  });

export const sendMorningFocusCompanion = functions.pubsub.schedule("30 9 * * *").onRun(async () => {
    functions.logger.info("Sending focus companion");
    await sendFocusCompanion();
  });

export const sendDailyGroupDigests = functions.pubsub.schedule("0 19 * * *").onRun(async () => {
    functions.logger.info("Sending group digests");
    await sendGroupDigests();
  });

// ── HTTPS Callable: AI Study ──────────────────────────────────────────────────

export const getAiStudy = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = request.auth.uid;
  const data = request.data as StudyContext & { passageId: string };

  // Check if cached in Firestore already
  const cacheRef = db
    .collection("studycache")
    .doc(uid)
    .collection("passages")
    .doc(data.passageId);

  const cached = await cacheRef.get();
  if (cached.exists) {
    const cacheData = cached.data()!;
    const cacheAge = Date.now() - (cacheData.cachedAt as admin.firestore.Timestamp).toMillis();
    // Cache for 7 days
    if (cacheAge < 7 * 24 * 60 * 60 * 1000) {
      return cacheData.study;
    }
  }

  // Check rate limit for free users
  const userSnap = await db.collection("users").doc(uid).get();
  const profile = userSnap.data()?.profile as Record<string, unknown>;
  const isPremium = profile?.isPremium as boolean;

  if (!isPremium) {
    const today = dateKey(new Date());
    const usageRef = db.collection("users").doc(uid).collection("aiUsage").doc(today);
    const usage = await usageRef.get();
    const questionsUsed = (usage.data()?.questionsUsed as number) ?? 0;
    if (questionsUsed >= 1) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Free limit: 1 AI question per day. Upgrade to Premium for unlimited."
      );
    }
    await usageRef.set(
      { questionsUsed: admin.firestore.FieldValue.increment(1) },
      { merge: true }
    );
  }

  const study = await generateAiStudy(data);

  // Cache the result
  await cacheRef.set({
    study,
    cachedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return study;
});

// ── HTTPS Callable: Sermon Debrief ────────────────────────────────────────────

export const generateDebrief = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = request.auth.uid;
  const data = request.data as DebriefContext;

  // Check usage limit for free users
  const userSnap = await db.collection("users").doc(uid).get();
  const profile = userSnap.data()?.profile as Record<string, unknown>;
  const isPremium = profile?.isPremium as boolean;

  if (!isPremium) {
    const monthKey = monthKeyStr(new Date());
    const usageRef = db.collection("users").doc(uid).collection("debriefUsage").doc(monthKey);
    const usage = await usageRef.get();
    const used = (usage.data()?.count as number) ?? 0;
    if (used >= 1) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Free limit: 1 AI debrief per month. Upgrade to Premium for unlimited."
      );
    }
    await usageRef.set({ count: admin.firestore.FieldValue.increment(1) }, { merge: true });
  }

  return generateSermonDebrief(data);
});

// ── HTTPS Callable: Suggest Sermon Title ─────────────────────────────────────

export const suggestTitle = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const { noteContent } = request.data as { noteContent: string };
  return { title: await suggestSermonTitle(noteContent) };
});

// ── HTTPS Callable: Record Session End ───────────────────────────────────────

export const recordSessionEnd = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = request.auth.uid;
  const { xpEarned } = request.data as {
    xpEarned: number;
    sessionType: string;
  };

  // Award XP
  await db.collection("users").doc(uid).update({
    "profile.xp": admin.firestore.FieldValue.increment(xpEarned),
  });

  // Update streak
  const streakResult = await recordStudyActivity(uid);

  // Check level up
  const userSnap = await db.collection("users").doc(uid).get();
  const profile = userSnap.data()?.profile as Record<string, unknown>;
  const newXp = (profile?.xp as number) ?? 0;
  const newLevel = levelForXp(newXp);
  const oldLevel = (profile?.level as number) ?? 1;

  if (newLevel > oldLevel) {
    await db.collection("users").doc(uid).update({ "profile.level": newLevel });
  }

  // Check XP milestone badges
  const prevXp = newXp - xpEarned;
  const newBadges = checkXpBadges(prevXp, newXp);
  for (const badge of newBadges) {
    await db.collection("badges").doc(uid).collection("earned").doc(badge).set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      shared: false,
      shareCount: 0,
    });
  }

  return {
    newStreak: streakResult.newStreak,
    leveledUp: newLevel > oldLevel,
    newLevel: newLevel > oldLevel ? newLevel : null,
    newBadges,
    streakBroken: streakResult.streakBroken,
    milestoneReached: streakResult.milestoneReached,
  };
});

// ── HTTPS Callable: Update Memory Verse (SM-2) ────────────────────────────────

export const updateMemoryVerse = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = request.auth.uid;
  const { verseId, percentCorrect } = request.data as {
    verseId: string;
    percentCorrect: number;
  };

  const verseRef = db
    .collection("memoryVerses")
    .doc(uid)
    .collection("verses")
    .doc(verseId);

  const snap = await verseRef.get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Verse not found");

  const data = snap.data()!;
  const card = {
    easeFactor: (data.easeFactor as number) ?? 250,
    interval: (data.interval as number) ?? 1,
    repetitions: (data.repetitions as number) ?? 0,
  };

  const grade = scoreToGrade(percentCorrect);
  const result = sm2Update(card, grade);

  await verseRef.update({
    easeFactor: result.easeFactor,
    interval: result.interval,
    repetitions: result.repetitions,
    lastReviewed: admin.firestore.FieldValue.serverTimestamp(),
    nextReviewDate: admin.firestore.Timestamp.fromDate(result.nextReviewDate),
    mastered: result.passed ? true : data.mastered,
  });

  return {
    passed: result.passed,
    nextReviewDays: result.interval,
    nextReviewDate: result.nextReviewDate.toISOString(),
  };
});

// ── HTTPS Callable: Register FCM Token ───────────────────────────────────────

export const registerFcmToken = functions.https.onCall(async (request) => {
  if (!request.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = request.auth.uid;
  const { token } = request.data as { token: string };

  await db.collection("users").doc(uid).collection("fcmTokens").doc(token).set({
    token,
    registeredAt: admin.firestore.FieldValue.serverTimestamp(),
    platform: "ios",
  });

  return { success: true };
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function dateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function monthKeyStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

const XP_LEVELS = [
  { level: 1, xp: 0 },
  { level: 2, xp: 500 },
  { level: 3, xp: 1500 },
  { level: 4, xp: 3500 },
  { level: 5, xp: 7000 },
  { level: 6, xp: 12000 },
  { level: 7, xp: 20000 },
];

function levelForXp(xp: number): number {
  let level = 1;
  for (const l of XP_LEVELS) {
    if (xp >= l.xp) level = l.level;
  }
  return level;
}

const XP_BADGE_MILESTONES: Record<number, string> = {
  100: "spark",
  500: "on_fire",
  1500: "burning_bright",
  3500: "unquenchable",
  7000: "flame_keeper",
  12000: "eternal_flame",
};

function checkXpBadges(oldXp: number, newXp: number): string[] {
  return Object.entries(XP_BADGE_MILESTONES)
    .filter(([threshold]) => oldXp < Number(threshold) && newXp >= Number(threshold))
    .map(([, badge]) => badge);
}

// ── Firestore Triggers: Auto-Post to Group Feed ──────────────────────────────

/**
 * When a badge is earned (written by recordSessionEnd), auto-post to all groups
 * the user belongs to if their autoPostSettings allows badge sharing.
 */
export const onBadgeEarned = functions.firestore
  .document("badges/{uid}/earned/{badgeId}")
  .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const badgeId = context.params.badgeId;

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";

    const BADGE_LABELS: Record<string, string> = {
      spark: "earned the Spark badge 🔥",
      on_fire: "earned the On Fire badge 🔥🔥",
      burning_bright: "is Burning Bright 🔥🔥🔥",
      unquenchable: "is Unquenchable 🔥🔥🔥🔥",
      flame_keeper: "is a Flame Keeper 🏆",
      eternal_flame: "is the Eternal Flame 🏆✨",
    };

    const label = BADGE_LABELS[badgeId] ?? `earned the ${badgeId} badge`;

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.badgeEarned !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "badgeEarned",
          authorId: uid,
          authorName: name,
          content: `${name} ${label}`,
          badgeId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

/**
 * When a memory verse is mastered (mastered field flips to true),
 * auto-post to groups.
 */
export const onMemoryVerseMastered = functions.firestore
  .document("memoryVerses/{uid}/verses/{verseId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before?.mastered || !after?.mastered) return; // only on first mastery

    const uid = context.params.uid;

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";
    const reference = (after.reference as string) ?? "a verse";

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.memoryVerseMastered !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "memoryVerseMastered",
          authorId: uid,
          authorName: name,
          content: `${name} just memorized ${reference}! 🧠✨`,
          verseReference: reference,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

/**
 * When a streak milestone is reached (recorded in streakMilestones sub-collection
 * by streak_manager.ts), auto-post to groups.
 */
export const onStreakMilestone = functions.firestore
  .document("users/{uid}/streakMilestones/{milestoneId}")
  .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const { days } = snap.data() as { days: number };

    const groupsSnap = await db
      .collection("groups")
      .where("memberIds", "array-contains", uid)
      .get();

    if (groupsSnap.empty) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const name = (userSnap.data()?.profile?.name as string) ?? "Someone";

    const writes: Promise<unknown>[] = [];
    for (const groupDoc of groupsSnap.docs) {
      const autoPost = groupDoc.data()?.autoPostSettings?.streakMilestone !== false;
      if (!autoPost) continue;

      writes.push(
        groupDoc.ref.collection("feed").add({
          type: "streakMilestone",
          authorId: uid,
          authorName: name,
          content: `${name} hit a ${days}-day streak! 🔥`,
          streakDays: days,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          comments: [],
          reactions: [],
        })
      );
    }
    await Promise.all(writes);
  });

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getTodaysPassages(): Promise<Array<{ id: string; text: string; reference: string }>> {
  // Simplified: return a hardcoded daily passage
  // In production: aggregate from active reading plans + featured passage
  return [
    {
      id: "john_3_16",
      text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
      reference: "John 3:16",
    },
  ];
}
