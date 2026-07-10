import * as admin from "firebase-admin";
import { sendPushNotification } from "./push_notifications";

const db = () => admin.firestore();

// Morning prompt variants — rotate so users don't see the same message twice in a row
const MORNING_PROMPTS = [
  "Good morning. The Word is ready when you are. 📖",
  "Start today anchored. Open Dig Deeper for your morning study.",
  "Before the day gets loud — one passage to ground you. 📖",
  "Your morning study is waiting. Even 5 minutes changes the day.",
  "New day, new depth. Open Dig Deeper and dig in.",
  "Scripture first. Everything else can wait 5 minutes.",
  "Good morning! Today's a great day to go deeper in the Word.",
  "The best way to start the day is in it. Open Dig Deeper. 📖",
  "Morning light. Morning Word. Open Dig Deeper.",
  "A verse a day. A study a week. A life transformed. Start now.",
];

const MORNING_VERSES: { reference: string; text: string }[] = [
  { reference: "Psalm 119:105", text: "Your word is a lamp to my feet and a light to my path." },
  { reference: "Joshua 1:8", text: "Keep this Book of the Law always on your lips; meditate on it day and night." },
  { reference: "Hebrews 4:12", text: "For the word of God is alive and active, sharper than any double-edged sword." },
  { reference: "Romans 15:4", text: "For everything that was written in the past was written to teach us." },
  { reference: "2 Timothy 3:16", text: "All Scripture is God-breathed and is useful for teaching, rebuking, correcting and training in righteousness." },
  { reference: "Psalm 1:2", text: "But whose delight is in the law of the LORD, and who meditates on his law day and night." },
  { reference: "Matthew 4:4", text: "Man shall not live on bread alone, but on every word that comes from the mouth of God." },
  { reference: "Isaiah 55:11", text: "So is my word that goes out from my mouth: It will not return to me empty." },
  { reference: "Deuteronomy 6:6", text: "These commandments that I give you today are to be on your hearts." },
  { reference: "Colossians 3:16", text: "Let the message of Christ dwell among you richly as you teach and admonish one another with all wisdom." },
];

/**
 * Sends a morning study reminder to all Dig Deeper users who have
 * opted in via preferences.focusCompanion = true.
 * Scheduled at 8:00am daily.
 */
export async function sendDigDeeperMorningReminder(): Promise<void> {
  // Find opted-in users
  const usersSnap = await db()
    .collection("users")
    .where("preferences.focusCompanion", "==", true)
    .get();

  if (usersSnap.empty) return;

  const dayOfYear = Math.floor(
    (Date.now() - new Date(new Date().getFullYear(), 0, 0).getTime()) / 86400000
  );
  const promptIdx = dayOfYear % MORNING_PROMPTS.length;

  // Use today's AI-generated focus verse from dailycache; fall back to hardcoded list
  let verse: { reference: string; text: string };
  try {
    const today = new Date().toISOString().split("T")[0];
    const cacheSnap = await db().collection("dailycache").doc(today).get();
    const focusVerse = cacheSnap.data()?.focusVerse as { reference: string; text: string } | undefined;
    verse = focusVerse ?? MORNING_VERSES[dayOfYear % MORNING_VERSES.length];
  } catch {
    verse = MORNING_VERSES[dayOfYear % MORNING_VERSES.length];
  }

  const body = `${verse.reference} — "${verse.text.length > 80 ? verse.text.slice(0, 79) + "…" : verse.text}"`;

  const promises = usersSnap.docs.map((doc) =>
    sendPushNotification({
      uid: doc.id,
      title: MORNING_PROMPTS[promptIdx],
      body,
      data: { type: "morning_reminder", reference: verse.reference },
      appFilter: "digdeeper",   // Only send to Dig Deeper FCM tokens
    })
  );

  await Promise.allSettled(promises);
}
