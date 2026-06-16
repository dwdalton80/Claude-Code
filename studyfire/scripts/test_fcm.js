const admin = require('./node_modules/firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require('../serviceAccountKey.json')) });
const db = admin.firestore();
const messaging = admin.messaging();

async function test() {
  const tokenSnap = await db.collection('users').doc('sVHG5SxfmkPjhchhlatDehkw26N2').collection('fcmTokens').get();
  console.log('tokens found:', tokenSnap.docs.length);
  const token = tokenSnap.docs[0]?.data().token;
  if (!token) { console.log('No token'); process.exit(); }
  const result = await messaging.send({
    token,
    notification: { title: 'Test Notification', body: 'This is a test from StudyFire' },
    apns: { payload: { aps: { sound: 'default', badge: 1 } } }
  });
  console.log('Send result:', result);
  process.exit();
}
test().catch(e => { console.error('Error:', e.message); process.exit(1); });
