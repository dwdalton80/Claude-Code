/**
 * import_asv.js
 *
 * Imports the ASV (American Standard Version) from the wldeh bible-api CDN
 * into your Firestore under the same structure as your existing versions:
 *
 *   bible/{version}/books/{bookId}/chapters/{chapterNum}/verses/{verseNum}
 *
 * Each verse doc: { text, verseNumber, reference, bookId, chapterNumber }
 *
 * Usage:
 *   1. cd studyfire/functions
 *   2. node ../scripts/import_asv.js
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS to be set, OR run inside the
 * functions directory where firebase-admin is already installed.
 *
 * Estimated time: ~20–40 minutes (31,102 verses, rate-limited to avoid CDN bans)
 */

const admin = require('firebase-admin');
const https = require('https');

// ── Init ──────────────────────────────────────────────────────────────────────

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

const VERSION = 'asv';
const CDN_VERSION = 'en-asv';
const BASE_URL = 'https://cdn.jsdelivr.net/gh/wldeh/bible-api/bibles';

// ── Book list (matches wldeh API slugs) ───────────────────────────────────────
// Format: [cdnSlug, firestoreId, chapterCount]
const BOOKS = [
  ['genesis',       'genesis',       50],
  ['exodus',        'exodus',        40],
  ['leviticus',     'leviticus',     27],
  ['numbers',       'numbers',       36],
  ['deuteronomy',   'deuteronomy',   34],
  ['joshua',        'joshua',        24],
  ['judges',        'judges',        21],
  ['ruth',          'ruth',           4],
  ['1samuel',       '1samuel',       31],
  ['2samuel',       '2samuel',       24],
  ['1kings',        '1kings',        22],
  ['2kings',        '2kings',        25],
  ['1chronicles',   '1chronicles',   29],
  ['2chronicles',   '2chronicles',   36],
  ['ezra',          'ezra',          10],
  ['nehemiah',      'nehemiah',      13],
  ['esther',        'esther',        10],
  ['job',           'job',           42],
  ['psalms',        'psalms',       150],
  ['proverbs',      'proverbs',      31],
  ['ecclesiastes',  'ecclesiastes',  12],
  ['songofsolomon', 'songofsolomon',  8],
  ['isaiah',        'isaiah',        66],
  ['jeremiah',      'jeremiah',      52],
  ['lamentations',  'lamentations',   5],
  ['ezekiel',       'ezekiel',       48],
  ['daniel',        'daniel',        12],
  ['hosea',         'hosea',         14],
  ['joel',          'joel',           3],
  ['amos',          'amos',           9],
  ['obadiah',       'obadiah',        1],
  ['jonah',         'jonah',          4],
  ['micah',         'micah',          7],
  ['nahum',         'nahum',          3],
  ['habakkuk',      'habakkuk',       3],
  ['zephaniah',     'zephaniah',      3],
  ['haggai',        'haggai',         2],
  ['zechariah',     'zechariah',     14],
  ['malachi',       'malachi',        4],
  ['matthew',       'matthew',       28],
  ['mark',          'mark',          16],
  ['luke',          'luke',          24],
  ['john',          'john',          21],
  ['acts',          'acts',          28],
  ['romans',        'romans',        16],
  ['1corinthians',  '1corinthians',  16],
  ['2corinthians',  '2corinthians',  13],
  ['galatians',     'galatians',      6],
  ['ephesians',     'ephesians',      6],
  ['philippians',   'philippians',    4],
  ['colossians',    'colossians',     4],
  ['1thessalonians','1thessalonians', 5],
  ['2thessalonians','2thessalonians', 3],
  ['1timothy',      '1timothy',       6],
  ['2timothy',      '2timothy',       4],
  ['titus',         'titus',          3],
  ['philemon',      'philemon',       1],
  ['hebrews',       'hebrews',       13],
  ['james',         'james',          5],
  ['1peter',        '1peter',         5],
  ['2peter',        '2peter',         3],
  ['1john',         '1john',          5],
  ['2john',         '2john',          1],
  ['3john',         '3john',          1],
  ['jude',          'jude',           1],
  ['revelation',    'revelation',    22],
];

// ── Helpers ───────────────────────────────────────────────────────────────────

function fetchJson(url, retries = 3) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', async () => {
        try {
          const parsed = JSON.parse(data);
          resolve(parsed);
        } catch (e) {
          if (retries > 0) {
            // Rate limited — wait 2s and retry
            await sleep(2000);
            fetchJson(url, retries - 1).then(resolve).catch(reject);
          } else {
            reject(new Error(`JSON parse error for ${url}: ${e.message}`));
          }
        }
      });
    }).on('error', async (err) => {
      if (retries > 0) {
        await sleep(2000);
        fetchJson(url, retries - 1).then(resolve).catch(reject);
      } else {
        reject(err);
      }
    });
  });
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

// Capitalize first letter for display reference (e.g. "genesis" → "Genesis")
function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// ── Main import ───────────────────────────────────────────────────────────────

async function importChapter(cdnBook, firestoreBook, chapter) {
  const url = `${BASE_URL}/${CDN_VERSION}/books/${cdnBook}/chapters/${chapter}.json`;
  let chapterData;

  try {
    chapterData = await fetchJson(url);
  } catch (e) {
    console.warn(`  ⚠ Failed to fetch ${cdnBook} ${chapter}: ${e.message}`);
    return 0;
  }

  // The chapter JSON has a "data" array: [{book, chapter, verse, text}, ...]
  const verses = chapterData.data || (Array.isArray(chapterData) ? chapterData : []);
  if (!verses.length) {
    console.warn(`  ⚠ Empty chapter: ${cdnBook} ${chapter}`);
    return 0;
  }

  const chapterRef = db
    .collection('bible').doc(VERSION)
    .collection('books').doc(firestoreBook)
    .collection('chapters').doc(String(chapter));

  // Write in chunks of 50 to avoid Firestore deadline timeouts
  const CHUNK_SIZE = 50;
  let count = 0;

  for (let i = 0; i < verses.length; i += CHUNK_SIZE) {
    const chunk = verses.slice(i, i + CHUNK_SIZE);
    const batch = db.batch();

    for (const v of chunk) {
      const verseNum = parseInt(v.verse || v.verseNumber || v.number, 10);
      const text = v.text || '';
      if (!verseNum || !text) continue;

      const bookDisplay = capitalize(cdnBook.replace(/-/g, ' '));
      const reference = `${bookDisplay} ${chapter}:${verseNum}`;

      const verseRef = chapterRef.collection('verses').doc(String(verseNum));
      batch.set(verseRef, {
        text,
        verseNumber: verseNum,
        reference,
        bookId: firestoreBook,
        chapterNumber: chapter,
      });
      count++;
    }

    await batch.commit();
  }

  return count;
}

async function main() {
  const resumeFrom = process.argv[2] || null; // e.g. node import_asv.js 1samuel
  console.log(`\n📖 Importing ASV into Firestore as version "${VERSION}"...`);
  if (resumeFrom) console.log(`   Resuming from: ${resumeFrom}`);
  console.log();

  let totalVerses = 0;
  let totalChapters = 0;
  const startTime = Date.now();
  let skipping = !!resumeFrom;

  for (const [cdnBook, firestoreBook, chapterCount] of BOOKS) {
    if (skipping) {
      if (firestoreBook === resumeFrom) skipping = false;
      else { console.log(`  ${cdnBook.padEnd(20)}skipped`); continue; }
    }
    process.stdout.write(`  ${cdnBook.padEnd(20)}`);
    let bookVerses = 0;

    for (let ch = 1; ch <= chapterCount; ch++) {
      const count = await importChapter(cdnBook, firestoreBook, ch);
      bookVerses += count;
      totalChapters++;
      // Delay between requests to avoid CDN rate limiting
      await sleep(500);
    }

    totalVerses += bookVerses;
    console.log(`✓ ${bookVerses} verses`);
  }

  const elapsed = Math.round((Date.now() - startTime) / 1000);
  console.log(`\n✅ Done! ${totalVerses} verses across ${totalChapters} chapters imported in ${elapsed}s`);
  console.log(`   Firestore path: bible/${VERSION}/books/{book}/chapters/{ch}/verses/{v}`);
}

main().catch(err => {
  console.error('Import failed:', err);
  process.exit(1);
});
