import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { generateSparkQuestion } from "./claude/spark_questions";
import { generateAiStudy, StudyContext } from "./claude/ai_study";
import { generateQuizBatch, generateWordOfDay } from "./claude/quiz_generation";
import { generateSermonDebrief, suggestSermonTitle, DebriefContext } from "./claude/sermon_debrief";
import { getClaudeClient, MODELS, StudyLevel, studyLevelInstructions } from "./claude/client";
import { recordStudyActivity, replenishGraceDays } from "./gamification/streak_manager";
import { sm2Update, scoreToGrade } from "./gamification/sm2_algorithm";
import {
  sendStreakReminders,
  sendFocusCompanion,
  sendGroupDigests,
  sendPushNotification,
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

    const now = new Date();
    const today = dateKey(now);
    const passages = getTodaysPassages(now);

    for (const passage of passages) {
      // Write manifest so the app knows which passageId to load today
      await db.collection("sparkcache").doc(today).set(
        { passageId: passage.id, reference: passage.reference },
        { merge: true }
      );

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

    // ── Word of Day ───────────────────────────────────────────────────────────
    try {
      // Use today's spark passage as the source
      const manifest = await db.collection("sparkcache").doc(today).get();
      if (manifest.exists) {
        const { passageId, reference } = manifest.data() as { passageId: string; reference: string };
        const sparkDoc = await db
          .collection("sparkcache").doc(today)
          .collection(passageId).doc("kjv").get();

        if (sparkDoc.exists) {
          const passageText = (sparkDoc.data() as { text: string }).text;
          const wordOfDay = await generateWordOfDay(passageText, reference, "kjv");
          await db.collection("dailycache").doc(today).set(
            { wordOfDay, generatedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
          );
          functions.logger.info("Word of day generated", { word: wordOfDay.word });
        }
      }
    } catch (err) {
      functions.logger.error("Word of day generation failed", err);
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

export const getAiStudy = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const data = reqData as StudyContext & { passageId: string };

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

  // TODO: re-enable premium check after RevenueCat setup

  const study = await generateAiStudy(data);

  // Cache the result
  await cacheRef.set({
    study,
    cachedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return study;
});

// ── HTTPS Callable: Sermon Debrief ────────────────────────────────────────────

export const generateDebrief = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }
  const raw = reqData ?? {};
  functions.logger.info("generateDebrief raw:", JSON.stringify(raw).substring(0, 200));
  try {
    const data: DebriefContext = {
      noteContent: raw.noteContent ?? raw.data?.noteContent ?? "",
      sermonTitle: raw.sermonTitle ?? raw.data?.sermonTitle,
      speaker: raw.speaker ?? raw.data?.speaker,
      scriptureRefs: raw.scriptureRefs ?? raw.data?.scriptureRefs ?? [],
      studyLevel: raw.studyLevel ?? raw.data?.studyLevel ?? "growing",
    };
    const result = await generateSermonDebrief(data);
    functions.logger.info("generateDebrief success");
    return result;
  } catch (err) {
    functions.logger.error("generateDebrief error", err);
    throw err;
  }
});

// ── HTTPS Callable: Suggest Sermon Title ─────────────────────────────────────

export const suggestTitle = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const { noteContent } = reqData as { noteContent: string };
  return { title: await suggestSermonTitle(noteContent) };
});

// ── HTTPS Callable: Record Session End ───────────────────────────────────────

export const recordSessionEnd = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { xpEarned } = reqData as {
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

export const updateMemoryVerse = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { verseId, percentCorrect } = reqData as {
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

export const registerFcmToken = functions.https.onCall(async (reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const uid = context.auth.uid;
  const { token } = reqData as { token: string };

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

// ── Firestore Trigger: Award XP Milestone Badges ─────────────────────────────

/**
 * Fires on every users/{uid} write. When profile.xp increases past a milestone
 * threshold, writes the badge to badges/{uid}/earned/{badgeId}. Server-side so
 * clients cannot self-award badges by writing directly to Firestore.
 */
export const onXpUpdated = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const oldXp = (change.before.data()?.profile?.xp as number) ?? 0;
    const newXp = (change.after.data()?.profile?.xp as number) ?? 0;

    if (newXp <= oldXp) return; // XP didn't increase — nothing to check

    const uid = context.params.uid;
    const newBadges = checkXpBadges(oldXp, newXp);
    if (newBadges.length === 0) return;

    await Promise.all(
      newBadges.map((badge) =>
        db
          .collection("badges")
          .doc(uid)
          .collection("earned")
          .doc(badge)
          .set(
            {
              earnedAt: admin.firestore.FieldValue.serverTimestamp(),
              shared: false,
              shareCount: 0,
            },
            { merge: true } // idempotent — safe if trigger fires more than once
          )
      )
    );
  });

// ── Firestore Triggers: Prayer Request Notifications ─────────────────────────

/**
 * When a new prayer request is created, notify all group members.
 */
export const onPrayerRequestCreated = functions.firestore
  .document("groups/{groupId}/prayers/{prayerId}")
  .onCreate(async (snap, context) => {
    const { groupId } = context.params;
    const prayer = snap.data();
    const authorName: string = prayer.authorName ?? "Someone";
    const text: string = prayer.text ?? "";
    const preview = text.length > 80 ? text.substring(0, 80) + "…" : text;

    // Get group name and members
    const [groupSnap, membersSnap] = await Promise.all([
      db.collection("groups").doc(groupId).get(),
      db.collection("groups").doc(groupId).collection("members").get(),
    ]);
    const groupName: string = (groupSnap.data()?.displayName ?? groupSnap.data()?.name ?? "Your Group") as string;

    const sends: Promise<void>[] = [];
    for (const memberDoc of membersSnap.docs) {
      const uid = memberDoc.id;
      if (uid === prayer.authorUid) continue; // don't notify the poster
      if (memberDoc.data()?.mutedNotifications === true) continue;
      sends.push(
        sendPushNotification({
          uid,
          title: `🙏 ${authorName} in ${groupName}`,
          body: preview,
          data: { type: "prayer_request", groupId, prayerId: snap.id },
        })
      );
    }
    await Promise.allSettled(sends);
  });

/**
 * When a prayer is marked answered, notify all group members so they can
 * celebrate together. The author already knows (they tapped the button), so
 * they are excluded from the notification batch.
 */
export const onPrayerAnswered = functions.firestore
  .document("groups/{groupId}/prayers/{prayerId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    // Only fire when answered flips true
    if (before.answered || !after.answered) return;

    const { groupId } = context.params;
    const authorUid: string = after.authorUid;
    const authorName: string = after.authorName ?? "Someone";

    const [groupSnap, membersSnap] = await Promise.all([
      db.collection("groups").doc(groupId).get(),
      db.collection("groups").doc(groupId).collection("members").get(),
    ]);
    const groupName: string = (groupSnap.data()?.displayName ?? groupSnap.data()?.name ?? "Your Group") as string;

    const sends: Promise<void>[] = [];
    for (const memberDoc of membersSnap.docs) {
      const uid = memberDoc.id;
      if (uid === authorUid) continue; // author already knows — they tapped the button
      if (memberDoc.data()?.mutedNotifications === true) continue;
      sends.push(
        sendPushNotification({
          uid,
          title: `✅ Prayer Answered in ${groupName}!`,
          body: `${authorName}'s prayer request was answered. Praise God! 🙌`,
          data: { type: "prayer_answered", groupId, prayerId: change.after.id },
        })
      );
    }
    await Promise.allSettled(sends);
  });

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
 * When a memory verse is added, award first_verse / ten_verses badges.
 */
export const onMemoryVerseAdded = functions.firestore
  .document("memoryVerses/{uid}/verses/{verseId}")
  .onCreate(async (_snap, context) => {
    const uid = context.params.uid;

    const versesSnap = await db
      .collection("memoryVerses")
      .doc(uid)
      .collection("verses")
      .get();
    const count = versesSnap.size;

    const badgeId = count === 1 ? "first_verse" : count === 10 ? "ten_verses" : null;
    if (!badgeId) return;

    const badgeRef = db.collection("badges").doc(uid).collection("earned").doc(badgeId);
    const existing = await badgeRef.get();
    if (existing.exists) return; // already earned

    const userSnap = await db.collection("users").doc(uid).get();
    const xp = (userSnap.data()?.profile?.xp as number) ?? 0;

    await badgeRef.set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      name: badgeId === "first_verse" ? "First Verse" : "Ten Verses",
      xpAtEarning: xp,
    });
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

// Curated passage rotation — cycles by day-of-year so each day gets fresh content.
// Add more passages to extend the rotation (aim for 52+ for a full year).
const PASSAGE_ROTATION: Array<{ id: string; text: string; reference: string }> = [
  { id: "jhn_3_16",  reference: "John 3:16",          text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life." },
  { id: "rom_8_28",  reference: "Romans 8:28",         text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose." },
  { id: "php_4_13",  reference: "Philippians 4:13",    text: "I can do all this through him who gives me strength." },
  { id: "jer_29_11", reference: "Jeremiah 29:11",      text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future." },
  { id: "psa_23_1",  reference: "Psalm 23:1",          text: "The Lord is my shepherd, I lack nothing." },
  { id: "pro_3_5",   reference: "Proverbs 3:5",        text: "Trust in the Lord with all your heart and lean not on your own understanding." },
  { id: "isa_40_31", reference: "Isaiah 40:31",        text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint." },
  { id: "mat_6_33",  reference: "Matthew 6:33",        text: "But seek first his kingdom and his righteousness, and all these things will be given to you as well." },
  { id: "rom_8_38",  reference: "Romans 8:38-39",      text: "For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord." },
  { id: "php_4_6",   reference: "Philippians 4:6-7",   text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus." },
  { id: "gal_2_20",  reference: "Galatians 2:20",      text: "I have been crucified with Christ and I no longer live, but Christ lives in me. The life I now live in the body, I live by faith in the Son of God, who loved me and gave himself for me." },
  { id: "psa_46_10", reference: "Psalm 46:10",         text: "He says, 'Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.'" },
  { id: "mat_11_28", reference: "Matthew 11:28-30",    text: "Come to me, all you who are weary and burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and humble in heart, and you will find rest for your souls. For my yoke is easy and my burden is light." },
  { id: "jhn_14_6",  reference: "John 14:6",           text: "Jesus answered, 'I am the way and the truth and the life. No one comes to the Father except through me.'" },
  { id: "rom_12_2",  reference: "Romans 12:2",         text: "Do not conform to the pattern of this world, but be transformed by the renewing of your mind. Then you will be able to test and approve what God's will is—his good, pleasing and perfect will." },
  { id: "eph_2_8",   reference: "Ephesians 2:8-9",     text: "For it is by grace you have been saved, through faith—and this is not from yourselves, it is the gift of God—not by works, so that no one can boast." },
  { id: "psa_139_14",reference: "Psalm 139:14",        text: "I praise you because I am fearfully and wonderfully made; your works are wonderful, I know that full well." },
  { id: "isa_41_10", reference: "Isaiah 41:10",        text: "So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand." },
  { id: "jhn_1_1",   reference: "John 1:1",            text: "In the beginning was the Word, and the Word was with God, and the Word was God." },
  { id: "1co_13_4",  reference: "1 Corinthians 13:4-7",text: "Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs. Love does not delight in evil but rejoices with the truth. It always protects, always trusts, always hopes, always perseveres." },
  { id: "psa_119_105",reference: "Psalm 119:105",      text: "Your word is a lamp for my feet, a light on my path." },
  { id: "mat_28_19", reference: "Matthew 28:19-20",    text: "Therefore go and make disciples of all nations, baptizing them in the name of the Father and of the Son and of the Holy Spirit, and teaching them to obey everything I have commanded you. And surely I am with you always, to the very end of the age." },
  { id: "rom_5_8",   reference: "Romans 5:8",          text: "But God demonstrates his own love for us in this: While we were still sinners, Christ died for us." },
  { id: "2co_5_17",  reference: "2 Corinthians 5:17",  text: "Therefore, if anyone is in Christ, the new creation has come: The old has gone, the new is here!" },
  { id: "eph_6_10",  reference: "Ephesians 6:10-11",   text: "Finally, be strong in the Lord and in his mighty power. Put on the full armor of God, so that you can take your stand against the devil's schemes." },
  { id: "heb_11_1",  reference: "Hebrews 11:1",        text: "Now faith is confidence in what we hope for and assurance about what we do not see." },
  { id: "jas_1_2",   reference: "James 1:2-4",         text: "Consider it pure joy, my brothers and sisters, whenever you face trials of many kinds, because you know that the testing of your faith produces perseverance. Let perseverance finish its work so that you may be mature and complete, not lacking anything." },
  { id: "1pe_5_7",   reference: "1 Peter 5:7",         text: "Cast all your anxiety on him because he cares for you." },
  { id: "1jn_4_19",  reference: "1 John 4:19",         text: "We love because he first loved us." },
  { id: "psa_27_1",  reference: "Psalm 27:1",          text: "The Lord is my light and my salvation—whom shall I fear? The Lord is the stronghold of my life—of whom shall I be afraid?" },
  { id: "luk_1_37",  reference: "Luke 1:37",           text: "For no word from God will ever fail." },
  { id: "rom_8_1",   reference: "Romans 8:1",          text: "Therefore, there is now no condemnation for those who are in Christ Jesus." },
  { id: "psa_34_18", reference: "Psalm 34:18",         text: "The Lord is close to the brokenhearted and saves those who are crushed in spirit." },
  { id: "isa_53_5",  reference: "Isaiah 53:5",         text: "But he was pierced for our transgressions, he was crushed for our iniquities; the punishment that brought us peace was on him, and by his wounds we are healed." },
  { id: "col_3_23",  reference: "Colossians 3:23-24",  text: "Whatever you do, work at it with all your heart, as working for the Lord, not for human masters, since you know that you will receive an inheritance from the Lord as a reward. It is the Lord Christ you are serving." },
  { id: "jhn_10_10", reference: "John 10:10",          text: "The thief comes only to steal and kill and destroy; I have come that they may have life, and have it to the full." },
  { id: "mat_5_14",  reference: "Matthew 5:14-16",     text: "You are the light of the world. A town built on a hill cannot be hidden. Neither do people light a lamp and put it under a bowl. Instead they put it on its stand, and it gives light to everyone in the house. In the same way, let your light shine before others, that they may see your good deeds and glorify your Father in heaven." },
  { id: "php_1_6",   reference: "Philippians 1:6",     text: "Being confident of this, that he who began a good work in you will carry it on to completion until the day of Christ Jesus." },
  { id: "2ti_1_7",   reference: "2 Timothy 1:7",       text: "For the Spirit God gave us does not make us timid, but gives us power, love and self-discipline." },
  { id: "psa_37_4",  reference: "Psalm 37:4",          text: "Take delight in the Lord, and he will give you the desires of your heart." },
  { id: "rom_15_13", reference: "Romans 15:13",        text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit." },
  { id: "heb_12_1",  reference: "Hebrews 12:1-2",      text: "Therefore, since we are surrounded by such a great cloud of witnesses, let us throw off everything that hinders and the sin that so easily entangles. And let us run with perseverance the race marked out for us, fixing our eyes on Jesus, the pioneer and perfecter of faith." },
  { id: "lam_3_22",  reference: "Lamentations 3:22-23",text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness." },
  { id: "gal_5_22",  reference: "Galatians 5:22-23",   text: "But the fruit of the Spirit is love, joy, peace, forbearance, kindness, goodness, faithfulness, gentleness and self-control. Against such things there is no law." },
  { id: "jhn_15_5",  reference: "John 15:5",           text: "I am the vine; you are the branches. If you remain in me and I in you, you will bear much fruit; apart from me you can do nothing." },
  { id: "mat_6_9",   reference: "Matthew 6:9-13",      text: "Our Father in heaven, hallowed be your name, your kingdom come, your will be done, on earth as it is in heaven. Give us today our daily bread. And forgive us our debts, as we also have forgiven our debtors. And lead us not into temptation, but deliver us from the evil one." },
  { id: "psa_91_1",  reference: "Psalm 91:1-2",        text: "Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty. I will say of the Lord, 'He is my refuge and my fortress, my God, in whom I trust.'" },
  { id: "eph_3_20",  reference: "Ephesians 3:20-21",   text: "Now to him who is able to do immeasurably more than all we ask or imagine, according to his power that is at work within us, to him be glory in the church and in Christ Jesus throughout all generations, for ever and ever! Amen." },
  { id: "act_1_8",   reference: "Acts 1:8",            text: "But you will receive power when the Holy Spirit comes on you; and you will be my witnesses in Jerusalem, and in all Judea and Samaria, and to the ends of the earth." },
  { id: "rev_3_20",  reference: "Revelation 3:20",     text: "Here I am! I stand at the door and knock. If anyone hears my voice and opens the door, I will come in and eat with that person, and they with me." },
  { id: "mic_6_8",   reference: "Micah 6:8",           text: "He has shown you, O mortal, what is good. And what does the Lord require of you? To act justly and to love mercy and to walk humbly with your God." },
  { id: "1co_10_13", reference: "1 Corinthians 10:13", text: "No temptation has overtaken you except what is common to mankind. And God is faithful; he will not let you be tempted beyond what you can bear. But when you are tempted, he will also provide a way out so that you can endure it." },
  { id: "deu_31_6",  reference: "Deuteronomy 31:6",    text: "Be strong and courageous. Do not be afraid or terrified because of them, for the Lord your God goes with you; he will never leave you nor forsake you." },
  { id: "2ch_7_14",  reference: "2 Chronicles 7:14",   text: "If my people, who are called by my name, will humble themselves and pray and seek my face and turn from their wicked ways, then I will hear from heaven, and I will forgive their sin and will heal their land." },
  { id: "psa_1_1",   reference: "Psalm 1:1-3",         text: "Blessed is the one who does not walk in step with the wicked or stand in the way that sinners take or sit in the company of mockers, but whose delight is in the law of the Lord, and who meditates on his law day and night. That person is like a tree planted by streams of water, which yields its fruit in season and whose leaf does not wither—whatever they do prospers." },
  { id: "jhn_8_32",  reference: "John 8:32",           text: "Then you will know the truth, and the truth will set you free." },
  { id: "rom_1_16",  reference: "Romans 1:16",         text: "For I am not ashamed of the gospel, because it is the power of God that brings salvation to everyone who believes: first to the Jew, then to the Gentile." },
];

function getTodaysPassages(date: Date = new Date()): Array<{ id: string; text: string; reference: string }> {
  // Pick passage by day-of-year so each day rotates automatically
  const start = new Date(date.getFullYear(), 0, 0);
  const diff = date.getTime() - start.getTime();
  const dayOfYear = Math.floor(diff / (1000 * 60 * 60 * 24));
  const index = dayOfYear % PASSAGE_ROTATION.length;
  return [PASSAGE_ROTATION[index]];
}

// ── HTTPS Callable: Word Study ────────────────────────────────────────────────
export const getWordStudy = functions.https.onCall(async (reqData, _context) => {
  const raw = reqData ?? {};
  const { word, verseRef, verseText } = raw;

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: "You are a Bible word study assistant. Always respond with valid JSON only, no other text.",
    messages: [{
      role: "user",
      content: `Do a word study on the word "${word}" from ${verseRef}: "${verseText}".

Return ONLY this JSON:
{
  "word": "${word}",
  "originalWord": "Hebrew or Greek word",
  "language": "Hebrew or Greek",
  "strongsNumber": "H1234 or G1234",
  "pronunciation": "phonetic pronunciation",
  "definition": "2-3 sentence definition focusing on biblical meaning",
  "usageInContext": "How this specific word is used in this verse and what it means here",
  "otherVerses": ["Reference 1", "Reference 2"],
  "applicationToday": "One practical sentence for modern application"
}`
    }]
  });

  const text = (response.content[0] as any).text;
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  return JSON.parse(text.substring(start, end + 1));
});

// ── HTTPS Callable: Ask Verse Question ───────────────────────────────────────

/** Per-feature daily limits for free users. */
const FREE_AI_LIMITS: Record<string, number> = {
  askVerseQuestion: 2,
  interpretVerse:   2,
  deepStudyVerse:   1,
  getVerseWordStudy: 2,
};

/**
 * Returns YYYY-MM-DD in UTC — used as the Firestore doc key for daily usage.
 */
function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Atomically increments the per-feature daily AI usage counter.
 * Returns { allowed: true, remaining } or { allowed: false, remaining: 0 }.
 * isPremium is read from Firestore — never trusted from the client.
 */
async function checkAndIncrementAiUsage(
  uid: string,
  feature: string
): Promise<{ allowed: boolean; remaining: number; limit: number }> {
  // Server-side isPremium check — ignore any value the client sends
  const userSnap = await db.collection("users").doc(uid).get();
  const isPremium = userSnap.data()?.profile?.isPremium === true;
  const limit = FREE_AI_LIMITS[feature] ?? 2;
  if (isPremium) return { allowed: true, remaining: 999, limit };

  const ref = db
    .collection("users")
    .doc(uid)
    .collection("aiUsage")
    .doc(`${feature}_${todayKey()}`);

  // Atomic increment + read in a transaction
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current: number = snap.exists ? (snap.data()?.count ?? 0) : 0;

    if (current >= limit) {
      return { allowed: false, remaining: 0, limit };
    }

    tx.set(ref, { count: current + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { allowed: true, remaining: limit - (current + 1), limit };
  });
}

export const askVerseQuestion = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText, question } = raw;

  if (!verseRef || !question) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or question");
  }

  // Require auth
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  // Rate-limit free users (isPremium verified server-side inside this function)
  const usage = await checkAndIncrementAiUsage(uid, "askVerseQuestion");
  if (!usage.allowed) {
    // Return a structured error the client can handle gracefully
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 400,
    system: "You are a helpful Bible study assistant. Give clear, practical answers in 2-4 sentences. Be warm and accessible.",
    messages: [{
      role: "user",
      content: `Verse: ${verseRef} - "${verseText}"\n\nQuestion: ${question}`
    }]
  });

  const answer = (response.content[0] as any).text;
  return { answer, remaining: usage.remaining };
});

/**
 * Premium: Greek / Hebrew word study for a verse.
 * Identifies 3-5 key original-language terms, returns transliteration,
 * Strong's number, literal meaning, and a plain-English insight.
 */
export const getVerseWordStudy = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw;

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  // Require auth
  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  // Word study counts against the daily limit (isPremium verified server-side)
  const usage = await checkAndIncrementAiUsage(uid, "getVerseWordStudy");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  // Determine testament from book abbreviation or reference
  // NT books start with: matt, mar, luke, joh, act, rom, 1co, 2co, gal, eph,
  // php, col, 1th, 2th, 1ti, 2ti, tit, phm, heb, jas, 1pe, 2pe, 1jo, 2jo,
  // 3jo, jude, rev
  const refLower = verseRef.toLowerCase();
  const ntPrefixes = ["matt","mar","luke","joh","act","rom","1co","2co","gal",
    "eph","php","col","1th","2th","1ti","2ti","tit","phm","heb","jas","1pe",
    "2pe","1jo","2jo","3jo","jude","rev"];
  const isNT = ntPrefixes.some((p) => refLower.startsWith(p));
  const lang = isNT ? "Greek (Koine)" : "Hebrew";

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: `You are a Biblical language scholar. When given a verse, identify 3-5 key ${lang} words
that unlock deeper meaning. For each word give:
- The English word from the verse
- Original ${lang} word (with transliteration)
- Strong's number
- Literal meaning
- One sentence on why it matters

Format your response as plain readable text (not JSON), using this pattern for each word:

**[English word]** — [Original word] ([transliteration], Strong's #XXXX)
Literal: [literal meaning]
Why it matters: [one warm, accessible sentence]

Keep the total response under 500 words. Warm, non-intimidating tone.`,
    messages: [{
      role: "user",
      content: `${verseRef}: "${verseText}"`
    }]
  });

  const answer = (response.content[0] as any).text;
  return { answer, remaining: usage.remaining };
});

/**
 * Retroactively checks and awards verse-count badges the onCreate trigger may
 * have missed (e.g. verses added before function was deployed).
 * Safe to call multiple times — skips already-earned badges.
 */
export const checkVerseBadges = functions.https.onCall(async (_reqData, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  const uid = context.auth.uid;

  const versesSnap = await db
    .collection("memoryVerses")
    .doc(uid)
    .collection("verses")
    .get();
  const count = versesSnap.size;

  const badgesToCheck: Array<{ id: string; name: string; threshold: number }> = [
    { id: "first_verse", name: "First Verse", threshold: 1 },
    { id: "ten_verses",  name: "Ten Verses",  threshold: 10 },
  ];

  const awarded: string[] = [];

  for (const badge of badgesToCheck) {
    if (count < badge.threshold) continue;
    const ref = db.collection("badges").doc(uid).collection("earned").doc(badge.id);
    const snap = await ref.get();
    if (snap.exists) continue; // already earned

    const userSnap = await db.collection("users").doc(uid).get();
    const xp = (userSnap.data()?.profile?.xp as number) ?? 0;
    await ref.set({
      earnedAt: admin.firestore.FieldValue.serverTimestamp(),
      name: badge.name,
      xpAtEarning: xp,
    });
    awarded.push(badge.id);
  }

  return { awarded, verseCount: count };
});

// ── HTTPS Callable: Search Verses ────────────────────────────────────────────

/**
 * Full-text keyword search across all Bible verses for a given version.
 * Uses collectionGroup('verses') + server-side JS includes() filtering since
 * Firestore does not support native substring/full-text search.
 *
 * Input:  { version: string, query: string }
 * Output: { results: Array<{ book, chapter, verse, reference, text }> }
 */
export const searchVerses = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (reqData, _context) => {
    const raw = (reqData ?? {}) as { version?: string; query?: string };
    const version = (raw.version ?? "kjv").trim().toLowerCase();
    const query = (raw.query ?? "").trim().toLowerCase();

    if (query.length < 3) {
      throw new functions.https.HttpsError("invalid-argument", "Query must be at least 3 characters");
    }

    // Use document ID ordering to restrict collectionGroup to just this version's path.
    // startAt/endAt on __name__ lets Firestore pre-filter without scanning other versions.
    const pathPrefix = `bible/${version}/`;
    const pathEnd = `bible/${version}/`;

    const snap = await db
      .collectionGroup("verses")
      .orderBy(admin.firestore.FieldPath.documentId())
      .startAt(pathPrefix)
      .endAt(pathEnd)
      .limit(40000)
      .get();

    const results: Array<{
      book: string;
      chapter: number;
      verse: number;
      reference: string;
      text: string;
    }> = [];

    for (const doc of snap.docs) {
      const data = doc.data();
      const text: string = data.text ?? data.verseText ?? "";
      if (!text.toLowerCase().includes(query)) continue;

      // Path: bible/{version}/books/{book}/chapters/{chapter}/verses/{id}
      const segments = doc.ref.path.split("/");
      const book = data.bookId ?? segments[3] ?? "";
      const chapter = data.chapterNumber ?? parseInt(segments[5] ?? "0", 10);
      const verse = data.verseNumber ?? 0;
      const reference = data.reference ?? `${book} ${chapter}:${verse}`;

      results.push({ book, chapter, verse, reference, text });
      if (results.length >= 30) break;
    }

    return { results };
  });

// ── HTTPS Callable: Interpret Verse ──────────────────────────────────────────

export const interpretVerse = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw as { verseRef: string; verseText: string };

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  const uid = context.auth?.uid;
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
  }

  const usage = await checkAndIncrementAiUsage(uid, "interpretVerse");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  // Fetch user study level for tone calibration
  const userSnap = await db.collection("users").doc(uid).get();
  const studyLevel: StudyLevel = (userSnap.data()?.profile?.studyLevel as StudyLevel) ?? "growing";
  const levelInstructions = studyLevelInstructions(studyLevel);

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 600,
    system: `You are a Bible study assistant for Joshua's Crossing, a Christian church in Denison, TX.
Interpret Scripture through the lens of these core beliefs:
- The Bible is the infallible, Holy Spirit-inspired Word of God and the sole foundation for faith and practice.
- God is the all-powerful, all-knowing, personal, and loving Creator of the Universe.
- Jesus is God incarnate — fully God and fully man — who lived a perfect life, died on the cross for the sins of the world, rose on the third day, ascended to Heaven, and is coming back.
- Salvation comes by trusting in Jesus as Lord; every person is sinful by nature and entry to Heaven is through faith in Christ alone.
- Baptism by full immersion is a public declaration of faith, not a requirement for salvation.
- The Church is the bride of Christ; every believer needs a church community.
- At death, every person goes to one of two eternal destinations: Heaven (with God) or Hell (apart from Him).
Give a concise verse interpretation (3-5 sentences) covering: (1) the plain meaning, (2) theological significance, (3) a brief application.
${levelInstructions}
Be warm, clear, and encouraging.`,
    messages: [{
      role: "user",
      content: `Interpret this verse:\n\n${verseRef} — "${verseText}"`
    }]
  });

  const answer = (response.content[0] as { type: "text"; text: string }).text;
  return { answer, remaining: usage.remaining };
});

// ── HTTPS Callable: Deep Study ────────────────────────────────────────────────

export const deepStudyVerse = functions.https.onCall(async (reqData, context) => {
  const raw = reqData ?? {};
  const { verseRef, verseText } = raw as { verseRef: string; verseText: string };

  if (!verseRef || !verseText) {
    throw new functions.https.HttpsError("invalid-argument", "Missing verseRef or verseText");
  }

  const uid = context.auth?.uid;
  if (!uid) throw new functions.https.HttpsError("unauthenticated", "Must be signed in");

  const usage = await checkAndIncrementAiUsage(uid, "deepStudyVerse");
  if (!usage.allowed) {
    return { error: "limit_reached", remaining: 0, limit: usage.limit };
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const studyLevel: StudyLevel = (userSnap.data()?.profile?.studyLevel as StudyLevel) ?? "growing";
  const levelInstructions = studyLevelInstructions(studyLevel);

  // Determine language (Greek for NT, Hebrew for OT)
  const refLower = verseRef.toLowerCase();
  const ntPrefixes = ["matt","mar","luke","joh","act","rom","1co","2co","gal",
    "eph","php","col","1th","2th","1ti","2ti","tit","phm","heb","jas","1pe",
    "2pe","1jo","2jo","3jo","jude","rev"];
  const lang = ntPrefixes.some((p) => refLower.startsWith(p)) ? "Greek (Koine)" : "Hebrew";

  const client = getClaudeClient();
  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 2000,
    system: `You are a Bible scholar for Joshua's Crossing, a Christian church in Denison, TX.
Ground all study content in these core beliefs:
- The Bible is the infallible, Holy Spirit-inspired Word of God — the only foundation for faith and practice.
- God is the all-powerful, all-knowing, personal, and loving Creator.
- Jesus is God incarnate — fully God and fully man — who died for the sins of the world, rose on the third day, ascended to Heaven, and is returning.
- Salvation is by faith in Jesus as Lord alone; humans are sinful by nature and cannot earn Heaven.
- Baptism by full immersion is a public declaration of new faith, not a requirement for salvation.
- The Church is the bride of Christ; community with other believers is essential.
- Eternity is real: Heaven for those who trust in Jesus, Hell for those who do not.
${levelInstructions}
Always respond with valid JSON only — no markdown fences, no extra text.`,
    messages: [{
      role: "user",
      content: `Generate a deep Bible study for this passage:

${verseRef}: "${verseText}"
Original language: ${lang}

Return ONLY this JSON structure:
{
  "verseClarity": {
    "context": "2-4 sentences explaining the historical, narrative, or literary context of this verse — who wrote it, to whom, and what was happening",
    "meaning": "3-5 sentences on the theological meaning of this specific verse — what it says about God, humanity, or salvation. Reference other parts of Scripture where helpful."
  },
  "wordStudy": [
    {
      "word": "English word from the verse",
      "originalWord": "${lang} word (use actual script if possible)",
      "transliteration": "phonetic transliteration",
      "strongsNumber": "H#### or G####",
      "definition": "1-2 sentence definition of the original word's core meaning",
      "scholarsInsight": "2-3 sentences connecting the word's original meaning to the theological significance in this passage"
    }
  ],
  "theologicalInsight": {
    "title": "Short doctrine or theme title (e.g. 'Providence: God's Sovereign Care')",
    "body": "3-4 sentences explaining the key theological doctrine or insight this verse teaches, grounded in the belief that Scripture is infallible, Jesus is the only path to salvation, and God is personal and loving",
    "scripturalSupport": [
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" },
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" },
      { "reference": "Book X:Y", "note": "One sentence on how this verse supports the insight" }
    ],
    "intellectualTakeaway": "One crisp sentence summarizing the deepest intellectual/theological takeaway from this verse"
  }
}

Include 2-4 key words in wordStudy. Pick the most theologically significant words.`
    }]
  });

  const raw2 = (response.content[0] as { type: "text"; text: string }).text.trim();
  const cleaned = raw2.replace(/^```json\n?/, "").replace(/^```\n?/, "").replace(/\n?```$/, "").trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  const parsed = JSON.parse(cleaned.substring(start, end + 1));
  return { ...parsed, remaining: usage.remaining };
});
