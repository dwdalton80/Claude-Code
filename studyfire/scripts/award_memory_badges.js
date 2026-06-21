/**
 * One-time script: retroactively award first_verse / ten_verses badges
 * for any user who already has memory verses but missing the badges.
 *
 * Usage:
 *   cd studyfire/functions
 *   GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json \
 *     node ../scripts/award_memory_badges.js
 *
 * Or from the project root with Application Default Credentials:
 *   firebase login (already done)
 *   node scripts/award_memory_badges.js
 */

const admin = require('firebase-admin');

// Uses Application Default Credentials (firebase login sets these up)
admin.initializeApp({ projectId: 'studyfire-11710' });
const db = admin.firestore();

async function run() {
  // Get all users who have memory verses
  const usersSnap = await db.collection('memoryVerses').get();

  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;

    const versesSnap = await db
      .collection('memoryVerses')
      .doc(uid)
      .collection('verses')
      .get();

    const count = versesSnap.size;
    console.log(`uid=${uid}  verses=${count}`);

    const badgesToCheck = [];
    if (count >= 1) badgesToCheck.push('first_verse');
    if (count >= 10) badgesToCheck.push('ten_verses');

    for (const badgeId of badgesToCheck) {
      const badgeRef = db
        .collection('badges')
        .doc(uid)
        .collection('earned')
        .doc(badgeId);

      const existing = await badgeRef.get();
      if (existing.exists) {
        console.log(`  ${badgeId}: already earned, skipping`);
        continue;
      }

      const userSnap = await db.collection('users').doc(uid).get();
      const xp = userSnap.data()?.profile?.xp ?? 0;

      await badgeRef.set({
        earnedAt: admin.firestore.FieldValue.serverTimestamp(),
        name: badgeId === 'first_verse' ? 'First Verse' : 'Ten Verses',
        xpAtEarning: xp,
      });
      console.log(`  ✓ awarded ${badgeId}`);
    }
  }

  console.log('\nDone.');
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
