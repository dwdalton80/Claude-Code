import * as admin from "firebase-admin";

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

export interface NotificationPayload {
  uid: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  imageUrl?: string;
}

export async function sendPushNotification(payload: NotificationPayload): Promise<void> {
  const tokenSnap = await db()
    .collection("users")
    .doc(payload.uid)
    .collection("fcmTokens")
    .get();

  if (tokenSnap.empty) return;

  const tokens = tokenSnap.docs.map((d) => d.data().token as string).filter(Boolean);
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
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
export async function sendStreakReminders(): Promise<void> {
  const today = new Date();
  const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());

  // Find users who haven't been active today
  const usersSnap = await db()
    .collection("users")
    .where("profile.lastActiveDate", "<", admin.firestore.Timestamp.fromDate(todayStart))
    .where("profile.streak", ">", 0)
    .get();

  const promises = usersSnap.docs.map(async (doc) => {
    const data = doc.data();
    const profile = data.profile as Record<string, unknown>;
    const prefs = (data.preferences ?? {}) as Record<string, unknown>;
    const uid = doc.id;

    // Respect user notification preferences (default true if not set)
    if (prefs.notificationsEnabled === false) return;
    if (prefs.streakReminderEnabled === false) return;

    // Get last used variant to avoid repeating
    const lastVariantIdx = (profile.lastStreakVariantIdx as number) ?? -1;
    let variantIdx = (lastVariantIdx + 1) % STREAK_VARIANTS.length;

    const streak = (profile.streak as number) ?? 0;
    const streakText = streak > 1 ? `Don't break your ${streak}-day streak! ` : "";
    const body = streakText + STREAK_VARIANTS[variantIdx];

    await sendPushNotification({
      uid,
      title: streak > 1 ? `🔥 ${streak}-Day Streak at Risk!` : "StudyFire 🔥",
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
export async function sendFocusCompanion(): Promise<void> {
  const today = new Date();
  const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;

  // Get today's verse from daily cache
  const cacheSnap = await db().collection("dailycache").doc(dateKey).get();
  const verse = cacheSnap.data()?.focusVerse as { text: string; reference: string } | undefined;
  if (!verse) return;

  // Find users who opted in to Focus Companion and have notifications enabled
  const usersSnap = await db()
    .collection("users")
    .where("preferences.notificationsEnabled", "!=", false)
    .get();

  const promises = usersSnap.docs.map(async (doc) => {
    const prefs = (doc.data().preferences ?? {}) as Record<string, unknown>;
    // Skip if user turned off morning focus companion (default true if not set)
    if (prefs.morningFocusEnabled === false) return;

    const uid = doc.id;
    const variantIdx = Math.floor(Math.random() * FOCUS_VARIANTS.length);
    const _title = FOCUS_VARIANTS[variantIdx]; void _title;

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
 * Respects per-user groupNotificationsEnabled preference (Firestore users/{uid}.preferences).
 * Skips groups with no activity in the past 24 hours.
 */
export async function sendGroupDigests(): Promise<void> {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);

  const groupsSnap = await db().collection("groups").get();

  for (const groupDoc of groupsSnap.docs) {
    const groupId = groupDoc.id;
    const groupName = (groupDoc.data().displayName ?? groupDoc.data().name ?? "Your Group") as string;

    // Count activity since yesterday
    const feedSnap = await db()
      .collection("groups")
      .doc(groupId)
      .collection("feed")
      .where("timestamp", ">", admin.firestore.Timestamp.fromDate(yesterday))
      .get();

    if (feedSnap.empty) continue;

    // Get all members — filter muted ones in code to avoid missing docs where field is absent
    const membersSnap = await db()
      .collection("groups")
      .doc(groupId)
      .collection("members")
      .get();

    const activityCount = feedSnap.size;

    for (const memberDoc of membersSnap.docs) {
      const memberData = memberDoc.data();
      // Skip if member explicitly muted this group
      if (memberData.mutedNotifications === true) continue;

      const uid = memberDoc.id;

      // Respect user-level group notification preference
      const userSnap = await db().collection("users").doc(uid).get();
      const prefs = (userSnap.data()?.preferences ?? {}) as Record<string, unknown>;
      if (prefs.notificationsEnabled === false) continue;
      if (prefs.groupNotificationsEnabled === false) continue;

      await sendPushNotification({
        uid,
        title: `📖 ${groupName}`,
        body: `${activityCount} new activit${activityCount === 1 ? "y" : "ies"} — see what your group is up to`,
        data: { type: "group_digest", groupId },
      });
    }
  }
}
