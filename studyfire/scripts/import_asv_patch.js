/**
 * import_asv_patch.js — re-imports specific missing chapters
 * Usage: GOOGLE_APPLICATION_CREDENTIALS=~/studyfire-service-account.json node ../scripts/import_asv_patch.js
 */

const admin = require('firebase-admin');
const https = require('https');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const VERSION = 'asv';
const CDN_VERSION = 'en-asv';
const BASE_URL = 'https://cdn.jsdelivr.net/gh/wldeh/bible-api/bibles';

// Chapters that failed due to rate limiting
const MISSING = [
  { cdnBook: 'acts',         firestoreBook: 'acts',         chapter: 24 },
  { cdnBook: '1corinthians', firestoreBook: '1corinthians', chapter: 8  },
  { cdnBook: 'ephesians',    firestoreBook: 'ephesians',    chapter: 4  },
];

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchJson(url, retries = 3) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', async () => {
        try { resolve(JSON.parse(data)); }
        catch (e) {
          if (retries > 0) { await sleep(3000); fetchJson(url, retries - 1).then(resolve).catch(reject); }
          else reject(new Error(`Parse error for ${url}: ${e.message}`));
        }
      });
    }).on('error', async (err) => {
      if (retries > 0) { await sleep(3000); fetchJson(url, retries - 1).then(resolve).catch(reject); }
      else reject(err);
    });
  });
}

async function main() {
  console.log('\n🔧 Patching missing ASV chapters...\n');

  for (const { cdnBook, firestoreBook, chapter } of MISSING) {
    const url = `${BASE_URL}/${CDN_VERSION}/books/${cdnBook}/chapters/${chapter}.json`;
    console.log(`  Fetching ${cdnBook} ${chapter}...`);
    await sleep(2000);

    const data = await fetchJson(url);
    const verses = data.data || [];

    const chapterRef = db.collection('bible').doc(VERSION)
      .collection('books').doc(firestoreBook)
      .collection('chapters').doc(String(chapter));

    const batch = db.batch();
    let count = 0;
    for (const v of verses) {
      const verseNum = parseInt(v.verse, 10);
      const text = v.text || '';
      if (!verseNum || !text) continue;
      const bookDisplay = v.book || cdnBook;
      batch.set(chapterRef.collection('verses').doc(String(verseNum)), {
        text,
        verseNumber: verseNum,
        reference: `${bookDisplay} ${chapter}:${verseNum}`,
        bookId: firestoreBook,
        chapterNumber: chapter,
      });
      count++;
    }
    await batch.commit();
    console.log(`  ✓ ${cdnBook} ${chapter} — ${count} verses`);
  }

  console.log('\n✅ Patch complete. ASV is fully imported.\n');
}

main().catch(err => { console.error('Patch failed:', err); process.exit(1); });
