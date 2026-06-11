"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onStreakMilestone = exports.onMemoryVerseMastered = exports.onBadgeEarned = exports.registerFcmToken = exports.updateMemoryVerse = exports.recordSessionEnd = exports.suggestTitle = exports.generateDebrief = exports.getAiStudy = exports.sendDailyGroupDigests = exports.sendMorningFocusCompanion = exports.sendEveningStreakReminders = exports.weeklyGraceReplenish = exports.generateDailyCache = exports.generateDailySpark = void 0;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const spark_questions_1 = require("./claude/spark_questions");
const ai_study_1 = require("./claude/ai_study");
const quiz_generation_1 = require("./claude/quiz_generation");
const sermon_debrief_1 = require("./claude/sermon_debrief");
const streak_manager_1 = require("./gamification/streak_manager");
const sm2_algorithm_1 = require("./gamification/sm2_algorithm");
const push_notifications_1 = require("./notifications/push_notifications");
admin.initializeApp();
const db = admin.firestore();
// ── Scheduled: 2am Daily ─────────────────────────────────────────────────────
/**
 * Pre-generates today's Spark question for each active passage.
 * One Claude call per passage, result shared with ALL free users.
 */
exports.generateDailySpark = functions.pubsub.schedule("0 2 * * *").onRun(async () => {
    functions.logger.info("Generating daily spark questions");
    const today = dateKey(new Date());
    // Get today's reading plan passages (simplified: iterate active plans)
    // In production: aggregate from readingPlan documents
    const passages = await getTodaysPassages();
    for (const passage of passages) {
        for (const version of ["kjv", "csb", "niv"]) {
            try {
                const question = await (0, spark_questions_1.generateSparkQuestion)(passage.text, passage.reference, version);
                await db
                    .collection("sparkcache")
                    .doc(today)
                    .collection(passage.id)
                    .doc(version)
                    .set({ ...question, generatedAt: admin.firestore.FieldValue.serverTimestamp() });
            }
            catch (err) {
                functions.logger.error(`Spark generation failed: ${passage.reference} ${version}`, err);
            }
        }
    }
});
/**
 * Pre-generates daily quiz questions and Word of the Day via Batch API.
 * 50% cost savings vs individual API calls.
 */
exports.generateDailyCache = functions.pubsub.schedule("30 2 * * *").onRun(async () => {
    functions.logger.info("Generating daily cache (quiz + word of day)");
    const today = dateKey(new Date());
    const topicTags = [
        "Anxiety & Fear", "Identity", "Purpose & Calling",
        "Forgiveness", "Prayer", "Relationships",
        "Doubt & Faith", "The Holy Spirit", "Suffering", "Spiritual Growth",
    ];
    try {
        const quizMap = await (0, quiz_generation_1.generateQuizBatch)(topicTags);
        const quizData = {};
        for (const [tag, questions] of quizMap.entries()) {
            quizData[tag] = questions;
        }
        await db.collection("dailycache").doc(today).set({ quizQuestions: quizData, generatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }
    catch (err) {
        functions.logger.error("Quiz batch generation failed", err);
    }
});
/**
 * Replenishes grace day tokens every Monday.
 */
exports.weeklyGraceReplenish = functions.pubsub.schedule("0 0 * * 1").onRun(async () => {
    functions.logger.info("Replenishing grace day tokens");
    await (0, streak_manager_1.replenishGraceDays)();
});
// ── Scheduled: Notifications ─────────────────────────────────────────────────
exports.sendEveningStreakReminders = functions.pubsub.schedule("0 20 * * *").onRun(async () => {
    functions.logger.info("Sending streak reminders");
    await (0, push_notifications_1.sendStreakReminders)();
});
exports.sendMorningFocusCompanion = functions.pubsub.schedule("30 9 * * *").onRun(async () => {
    functions.logger.info("Sending focus companion");
    await (0, push_notifications_1.sendFocusCompanion)();
});
exports.sendDailyGroupDigests = functions.pubsub.schedule("0 19 * * *").onRun(async () => {
    functions.logger.info("Sending group digests");
    await (0, push_notifications_1.sendGroupDigests)();
});
// ── HTTPS Callable: AI Study ──────────────────────────────────────────────────
exports.getAiStudy = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const uid = request.auth.uid;
    const data = request.data;
    // Check if cached in Firestore already
    const cacheRef = db
        .collection("studycache")
        .doc(uid)
        .collection("passages")
        .doc(data.passageId);
    const cached = await cacheRef.get();
    if (cached.exists) {
        const cacheData = cached.data();
        const cacheAge = Date.now() - cacheData.cachedAt.toMillis();
        // Cache for 7 days
        if (cacheAge < 7 * 24 * 60 * 60 * 1000) {
            return cacheData.study;
        }
    }
    // Check rate limit for free users
    const userSnap = await db.collection("users").doc(uid).get();
    const profile = userSnap.data()?.profile;
    const isPremium = profile?.isPremium;
    if (!isPremium) {
        const today = dateKey(new Date());
        const usageRef = db.collection("users").doc(uid).collection("aiUsage").doc(today);
        const usage = await usageRef.get();
        const questionsUsed = usage.data()?.questionsUsed ?? 0;
        if (questionsUsed >= 1) {
            throw new functions.https.HttpsError("resource-exhausted", "Free limit: 1 AI question per day. Upgrade to Premium for unlimited.");
        }
        await usageRef.set({ questionsUsed: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }
    const study = await (0, ai_study_1.generateAiStudy)(data);
    // Cache the result
    await cacheRef.set({
        study,
        cachedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return study;
});
// ── HTTPS Callable: Sermon Debrief ────────────────────────────────────────────
exports.generateDebrief = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const uid = request.auth.uid;
    const data = request.data;
    // Check usage limit for free users
    const userSnap = await db.collection("users").doc(uid).get();
    const profile = userSnap.data()?.profile;
    const isPremium = profile?.isPremium;
    if (!isPremium) {
        const monthKey = monthKeyStr(new Date());
        const usageRef = db.collection("users").doc(uid).collection("debriefUsage").doc(monthKey);
        const usage = await usageRef.get();
        const used = usage.data()?.count ?? 0;
        if (used >= 1) {
            throw new functions.https.HttpsError("resource-exhausted", "Free limit: 1 AI debrief per month. Upgrade to Premium for unlimited.");
        }
        await usageRef.set({ count: admin.firestore.FieldValue.increment(1) }, { merge: true });
    }
    return (0, sermon_debrief_1.generateSermonDebrief)(data);
});
// ── HTTPS Callable: Suggest Sermon Title ─────────────────────────────────────
exports.suggestTitle = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const { noteContent } = request.data;
    return { title: await (0, sermon_debrief_1.suggestSermonTitle)(noteContent) };
});
// ── HTTPS Callable: Record Session End ───────────────────────────────────────
exports.recordSessionEnd = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const uid = request.auth.uid;
    const { xpEarned } = request.data;
    // Award XP
    await db.collection("users").doc(uid).update({
        "profile.xp": admin.firestore.FieldValue.increment(xpEarned),
    });
    // Update streak
    const streakResult = await (0, streak_manager_1.recordStudyActivity)(uid);
    // Check level up
    const userSnap = await db.collection("users").doc(uid).get();
    const profile = userSnap.data()?.profile;
    const newXp = profile?.xp ?? 0;
    const newLevel = levelForXp(newXp);
    const oldLevel = profile?.level ?? 1;
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
exports.updateMemoryVerse = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const uid = request.auth.uid;
    const { verseId, percentCorrect } = request.data;
    const verseRef = db
        .collection("memoryVerses")
        .doc(uid)
        .collection("verses")
        .doc(verseId);
    const snap = await verseRef.get();
    if (!snap.exists)
        throw new functions.https.HttpsError("not-found", "Verse not found");
    const data = snap.data();
    const card = {
        easeFactor: data.easeFactor ?? 250,
        interval: data.interval ?? 1,
        repetitions: data.repetitions ?? 0,
    };
    const grade = (0, sm2_algorithm_1.scoreToGrade)(percentCorrect);
    const result = (0, sm2_algorithm_1.sm2Update)(card, grade);
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
exports.registerFcmToken = functions.https.onCall(async (request) => {
    if (!request.auth)
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    const uid = request.auth.uid;
    const { token } = request.data;
    await db.collection("users").doc(uid).collection("fcmTokens").doc(token).set({
        token,
        registeredAt: admin.firestore.FieldValue.serverTimestamp(),
        platform: "ios",
    });
    return { success: true };
});
// ── Helpers ───────────────────────────────────────────────────────────────────
function dateKey(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function monthKeyStr(d) {
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
function levelForXp(xp) {
    let level = 1;
    for (const l of XP_LEVELS) {
        if (xp >= l.xp)
            level = l.level;
    }
    return level;
}
const XP_BADGE_MILESTONES = {
    100: "spark",
    500: "on_fire",
    1500: "burning_bright",
    3500: "unquenchable",
    7000: "flame_keeper",
    12000: "eternal_flame",
};
function checkXpBadges(oldXp, newXp) {
    return Object.entries(XP_BADGE_MILESTONES)
        .filter(([threshold]) => oldXp < Number(threshold) && newXp >= Number(threshold))
        .map(([, badge]) => badge);
}
// ── Firestore Triggers: Auto-Post to Group Feed ──────────────────────────────
/**
 * When a badge is earned (written by recordSessionEnd), auto-post to all groups
 * the user belongs to if their autoPostSettings allows badge sharing.
 */
exports.onBadgeEarned = functions.firestore
    .document("badges/{uid}/earned/{badgeId}")
    .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const badgeId = context.params.badgeId;
    const groupsSnap = await db
        .collection("groups")
        .where("memberIds", "array-contains", uid)
        .get();
    if (groupsSnap.empty)
        return;
    const userSnap = await db.collection("users").doc(uid).get();
    const name = userSnap.data()?.profile?.name ?? "Someone";
    const BADGE_LABELS = {
        spark: "earned the Spark badge 🔥",
        on_fire: "earned the On Fire badge 🔥🔥",
        burning_bright: "is Burning Bright 🔥🔥🔥",
        unquenchable: "is Unquenchable 🔥🔥🔥🔥",
        flame_keeper: "is a Flame Keeper 🏆",
        eternal_flame: "is the Eternal Flame 🏆✨",
    };
    const label = BADGE_LABELS[badgeId] ?? `earned the ${badgeId} badge`;
    const writes = [];
    for (const groupDoc of groupsSnap.docs) {
        const autoPost = groupDoc.data()?.autoPostSettings?.badgeEarned !== false;
        if (!autoPost)
            continue;
        writes.push(groupDoc.ref.collection("feed").add({
            type: "badgeEarned",
            authorId: uid,
            authorName: name,
            content: `${name} ${label}`,
            badgeId,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            comments: [],
            reactions: [],
        }));
    }
    await Promise.all(writes);
});
/**
 * When a memory verse is mastered (mastered field flips to true),
 * auto-post to groups.
 */
exports.onMemoryVerseMastered = functions.firestore
    .document("memoryVerses/{uid}/verses/{verseId}")
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before?.mastered || !after?.mastered)
        return; // only on first mastery
    const uid = context.params.uid;
    const groupsSnap = await db
        .collection("groups")
        .where("memberIds", "array-contains", uid)
        .get();
    if (groupsSnap.empty)
        return;
    const userSnap = await db.collection("users").doc(uid).get();
    const name = userSnap.data()?.profile?.name ?? "Someone";
    const reference = after.reference ?? "a verse";
    const writes = [];
    for (const groupDoc of groupsSnap.docs) {
        const autoPost = groupDoc.data()?.autoPostSettings?.memoryVerseMastered !== false;
        if (!autoPost)
            continue;
        writes.push(groupDoc.ref.collection("feed").add({
            type: "memoryVerseMastered",
            authorId: uid,
            authorName: name,
            content: `${name} just memorized ${reference}! 🧠✨`,
            verseReference: reference,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            comments: [],
            reactions: [],
        }));
    }
    await Promise.all(writes);
});
/**
 * When a streak milestone is reached (recorded in streakMilestones sub-collection
 * by streak_manager.ts), auto-post to groups.
 */
exports.onStreakMilestone = functions.firestore
    .document("users/{uid}/streakMilestones/{milestoneId}")
    .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const { days } = snap.data();
    const groupsSnap = await db
        .collection("groups")
        .where("memberIds", "array-contains", uid)
        .get();
    if (groupsSnap.empty)
        return;
    const userSnap = await db.collection("users").doc(uid).get();
    const name = userSnap.data()?.profile?.name ?? "Someone";
    const writes = [];
    for (const groupDoc of groupsSnap.docs) {
        const autoPost = groupDoc.data()?.autoPostSettings?.streakMilestone !== false;
        if (!autoPost)
            continue;
        writes.push(groupDoc.ref.collection("feed").add({
            type: "streakMilestone",
            authorId: uid,
            authorName: name,
            content: `${name} hit a ${days}-day streak! 🔥`,
            streakDays: days,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            comments: [],
            reactions: [],
        }));
    }
    await Promise.all(writes);
});
// ── Helpers ───────────────────────────────────────────────────────────────────
async function getTodaysPassages() {
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
//# sourceMappingURL=index.js.map