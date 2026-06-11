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
exports.sendPushNotification = sendPushNotification;
exports.sendStreakReminders = sendStreakReminders;
exports.sendFocusCompanion = sendFocusCompanion;
exports.sendGroupDigests = sendGroupDigests;
const admin = __importStar(require("firebase-admin"));
const messaging = () => admin.messaging();
const db = () => admin.firestore();
// Streak reminder variants — never repeat two in a row
const STREAK_VARIANTS = [
    "Your streak is waiting. 90 seconds. That's all. 🔥",
    "Don't let today be the day the flame goes out.",
    "Romans 8 isn't going to read itself. (Tap here.)",
    "Your streak is still alive. Keep it that way. ⚡",
    "Even 60 seconds counts. You've got this.",
    "Scripture is best absorbed daily. Today's your day.",
    "The Scribe in you is ready. Open StudyFire.",
    "Quick check-in: Has today's verse spoken to you yet?",
    "60 seconds. One verse. That's your whole challenge today.",
    "Your flame is waiting to be ignited. 🔥",
    "Missing today would break your streak. Don't miss today.",
    "You opened the app yesterday. Do it again today.",
    "Small daily steps > occasional big leaps. Today's step awaits.",
    "Someone in your group already studied today. Your turn?",
    "One verse. One question. One win. Tap to start.",
];
// Focus Companion variants (morning verse + reflection)
const FOCUS_VARIANTS = [
    "Start your morning anchored. Today's verse is waiting. 🔥",
    "Before the day gets loud — one verse to ground you.",
    "Your morning anchor is ready. 30 seconds to start well.",
    "Good morning! A verse is waiting for you in StudyFire.",
    "Begin today in the Word. Takes less than a minute.",
];
async function sendPushNotification(payload) {
    const tokenSnap = await db()
        .collection("users")
        .doc(payload.uid)
        .collection("fcmTokens")
        .get();
    if (tokenSnap.empty)
        return;
    const tokens = tokenSnap.docs.map((d) => d.data().token).filter(Boolean);
    if (tokens.length === 0)
        return;
    const message = {
        tokens,
        notification: {
            title: payload.title,
            body: payload.body,
            imageUrl: payload.imageUrl,
        },
        data: payload.data ?? {},
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
    };
    await messaging().sendEachForMulticast(message);
}
/**
 * Sends streak reminder to users who haven't studied today.
 * Called at 8pm daily via Cloud Scheduler.
 */
async function sendStreakReminders() {
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    // Find users who haven't been active today
    const usersSnap = await db()
        .collection("users")
        .where("profile.lastActiveDate", "<", admin.firestore.Timestamp.fromDate(todayStart))
        .where("profile.streak", ">", 0)
        .get();
    const promises = usersSnap.docs.map(async (doc) => {
        const profile = doc.data().profile;
        const uid = doc.id;
        // Get last used variant to avoid repeating
        const lastVariantIdx = profile.lastStreakVariantIdx ?? -1;
        let variantIdx = (lastVariantIdx + 1) % STREAK_VARIANTS.length;
        const body = STREAK_VARIANTS[variantIdx];
        await sendPushNotification({
            uid,
            title: "StudyFire 🔥",
            body,
            data: { type: "streak_reminder", action: "open_quest" },
        });
        // Update last variant index
        await doc.ref.update({ "profile.lastStreakVariantIdx": variantIdx });
    });
    await Promise.allSettled(promises);
}
/**
 * Sends Focus Companion morning verse to opted-in users.
 * Called at 9:30am daily via Cloud Scheduler.
 */
async function sendFocusCompanion() {
    const today = new Date();
    const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    // Get today's verse from daily cache
    const cacheSnap = await db().collection("dailycache").doc(dateKey).get();
    const verse = cacheSnap.data()?.focusVerse;
    if (!verse)
        return;
    // Find users who opted in to Focus Companion
    const usersSnap = await db()
        .collection("users")
        .where("preferences.focusCompanion", "==", true)
        .get();
    const promises = usersSnap.docs.map(async (doc) => {
        const uid = doc.id;
        const variantIdx = Math.floor(Math.random() * FOCUS_VARIANTS.length);
        const _title = FOCUS_VARIANTS[variantIdx];
        void _title;
        await sendPushNotification({
            uid,
            title: "StudyFire — Morning Verse",
            body: `${verse.reference}: "${verse.text.slice(0, 80)}${verse.text.length > 80 ? "…" : ""}"`,
            data: { type: "focus_companion", reference: verse.reference },
        });
    });
    await Promise.allSettled(promises);
}
/**
 * Sends daily group digest — single notification summarizing group activity.
 * Replaces per-reaction/comment notifications.
 */
async function sendGroupDigests() {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const groupsSnap = await db().collection("groups").get();
    for (const groupDoc of groupsSnap.docs) {
        const groupId = groupDoc.id;
        const groupName = groupDoc.data().name;
        // Count activity since yesterday
        const feedSnap = await db()
            .collection("groups")
            .doc(groupId)
            .collection("feed")
            .where("timestamp", ">", admin.firestore.Timestamp.fromDate(yesterday))
            .get();
        if (feedSnap.empty)
            continue;
        // Get members who want group notifications
        const membersSnap = await db()
            .collection("groups")
            .doc(groupId)
            .collection("members")
            .where("mutedNotifications", "==", false)
            .get();
        const activityCount = feedSnap.size;
        for (const memberDoc of membersSnap.docs) {
            const uid = memberDoc.id;
            await sendPushNotification({
                uid,
                title: groupName,
                body: `${activityCount} new activit${activityCount === 1 ? "y" : "ies"} in your group`,
                data: { type: "group_digest", groupId },
            });
        }
    }
}
//# sourceMappingURL=push_notifications.js.map