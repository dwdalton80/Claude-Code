#!/usr/bin/env node
/**
 * One-time Bible import script.
 *
 * Bulk-loads KJV, CSB, and NIV from API.Bible into Firestore.
 * Firestore path: bible/{version}/books/{bookId}/chapters/{chapterNum}/verses/{verseNum}
 *
 * Prerequisites:
 *   npm install firebase-admin node-fetch@2 dotenv
 *
 * Usage:
 *   API_BIBLE_KEY=your_key \
 *   FIREBASE_SERVICE_ACCOUNT=./serviceAccountKey.json \
 *   node scripts/import-bible.js [--version kjv] [--book GEN] [--dry-run]
 *
 * API.Bible version IDs:
 *   KJV:  de4e12af7f28f599-02
 *   CSB:  a556c5305ee15c3f-01  (closest available: HCSB 1999)
 *   NIV:  78a9f6124f344018-01
 *
 * Run once per version. Takes ~30 min per version. Costs ~100k Firestore writes.
 */

require("dotenv").config();
const admin = require("firebase-admin");
const fetch = require("node-fetch");
const path = require("path");

// ── Config ───────────────────────────────────────────────────────────────────

const API_KEY = process.env.API_BIBLE_KEY;
if (!API_KEY) {
  console.error("Missing API_BIBLE_KEY env var");
  process.exit(1);
}

const SERVICE_ACCOUNT = process.env.FIREBASE_SERVICE_ACCOUNT || "./serviceAccountKey.json";
admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(SERVICE_ACCOUNT))),
});
const db = admin.firestore();

// Parse CLI flags
const args = process.argv.slice(2);
const FLAG = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : null;
};
const HAS = (flag) => args.includes(flag);

const VERSION_ARG = FLAG("--version"); // e.g. "kjv" | "csb" | "niv"
const BOOK_ARG = FLAG("--book");       // e.g. "GEN" — resume from this book
const DRY_RUN = HAS("--dry-run");

// ── API.Bible version IDs ─────────────────────────────────────────────────────

const VERSION_IDS = {
  kjv: "de4e12af7f28f599-02",
  niv: "78a9f6124f344018-01",
  csb: "a556c5305ee15c3f-01",
};

const VERSIONS_TO_IMPORT = VERSION_ARG
  ? [VERSION_ARG]
  : Object.keys(VERSION_IDS);

// ── Helpers ───────────────────────────────────────────────────────────────────

const API_BASE = "https://api.scripture.api.bible/v1";

async function apiBible(path) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "api-key": API_KEY },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API.Bible ${path} → ${res.status}: ${body}`);
  }
  const json = await res.json();
  return json.data;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// Commit batch and start new one
async function flushBatch(batch, count) {
  if (DRY_RUN) {
    console.log(`[dry-run] Would write ${count} docs`);
    return db.batch();
  }
  await batch.commit();
  return db.batch();
}

// ── Core import logic ─────────────────────────────────────────────────────────

async function importVersion(versionKey) {
  const bibleId = VERSION_IDS[versionKey];
  console.log(`\n========== Importing ${versionKey.toUpperCase()} (${bibleId}) ==========`);

  const books = await apiBible(`/bibles/${bibleId}/books`);
  console.log(`${books.length} books found`);

  // Find start position if --book was given
  const startIndex = BOOK_ARG
    ? books.findIndex((b) => b.id === BOOK_ARG.toUpperCase())
    : 0;

  if (startIndex < 0) {
    console.error(`Book ${BOOK_ARG} not found`);
    process.exit(1);
  }

  let batch = db.batch();
  let batchCount = 0;
  let totalVerses = 0;

  for (let bi = startIndex; bi < books.length; bi++) {
    const book = books[bi];
    console.log(`[${bi + 1}/${books.length}] ${book.name} (${book.id})`);

    const chapters = await apiBible(`/bibles/${bibleId}/books/${book.id}/chapters`);

    for (const chapter of chapters) {
      // Skip intro chapters (often id like "GEN.intro")
      if (!chapter.id.match(/\.\d+$/)) continue;

      const chapterNum = parseInt(chapter.number, 10);
      const chapterData = await apiBible(
        `/bibles/${bibleId}/chapters/${chapter.id}?content-type=json&include-verse-numbers=true&include-notes=false`
      );

      const verses = extractVerses(chapterData);

      for (const verse of verses) {
        const ref = db
          .collection("bible")
          .doc(versionKey)
          .collection("books")
          .doc(book.id.toLowerCase())
          .collection("chapters")
          .doc(String(chapterNum))
          .collection("verses")
          .doc(String(verse.number));

        batch.set(ref, {
          verseNumber: verse.number,
          text: verse.text,
          reference: `${book.name} ${chapterNum}:${verse.number}`,
          bookId: book.id.toLowerCase(),
          bookName: book.name,
          testament: getTestament(book.id),
          chapterNumber: chapterNum,
          version: versionKey,
        });

        batchCount++;
        totalVerses++;

        if (batchCount >= 400) {
          batch = await flushBatch(batch, batchCount);
          batchCount = 0;
          await sleep(200); // avoid Firestore rate limits
        }
      }

      await sleep(100); // API.Bible rate limit: ~100 req/min
    }
  }

  // Flush remaining
  if (batchCount > 0) {
    await flushBatch(batch, batchCount);
  }

  console.log(`✅ ${versionKey.toUpperCase()} done — ${totalVerses} verses imported`);
}

// ── Parse API.Bible JSON content into flat verse array ────────────────────────

function extractVerses(chapterData) {
  const verses = [];
  const verseMap = {};

  function walk(nodes) {
    if (!nodes || !Array.isArray(nodes)) return;
    for (const node of nodes) {
      if (!node) continue;
      // Verse marker tag
      if (node.type === 'tag' && node.name === 'verse' && node.attrs?.number) {
        const num = parseInt(node.attrs.number, 10);
        if (!verseMap[num]) verseMap[num] = '';
      }
      // Text node with verseId attribute
      if (node.type === 'text' && node.text && node.attrs?.verseId) {
        const parts = node.attrs.verseId.split('.');
        const num = parseInt(parts[2], 10);
        if (num) verseMap[num] = (verseMap[num] || '') + node.text;
      }
      // Recurse into items or content
      if (node.items) walk(node.items);
      if (node.content) walk(node.content);
    }
  }

  walk(chapterData.content || chapterData);

  for (const [num, text] of Object.entries(verseMap)) {
    const cleaned = text.trim();
    if (cleaned) verses.push({ number: parseInt(num, 10), text: cleaned });
  }

  return verses.sort((a, b) => a.number - b.number);
}

function collectText(nodes) {
  if (!nodes) return "";
  return nodes
    .map((n) => {
      if (typeof n === "string") return n;
      if (n.type === "text") return n.text || "";
      if (n.content) return collectText(n.content);
      return "";
    })
    .join("");
}

function getTestament(bookId) {
  const NT_BOOKS = new Set([
    "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
    "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM",
    "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
  ]);
  return NT_BOOKS.has(bookId) ? "nt" : "ot";
}

// ── Also write a flat search index (book-level) ───────────────────────────────

async function writeSearchIndex(versionKey) {
  console.log(`\nWriting search index for ${versionKey}...`);
  // The search index maps "book:chapter" → list of verse refs for Browse tab
  // Production: Cloud Function aggregates on write; here we write a shallow manifest
  const manifest = { version: versionKey, importedAt: admin.firestore.FieldValue.serverTimestamp() };

  if (!DRY_RUN) {
    await db.collection("bibleManifest").doc(versionKey).set(manifest, { merge: true });
  }
  console.log("  manifest written");
}

// ── Main ──────────────────────────────────────────────────────────────────────

(async () => {
  try {
    for (const version of VERSIONS_TO_IMPORT) {
      if (!VERSION_IDS[version]) {
        console.error(`Unknown version: ${version}. Use: ${Object.keys(VERSION_IDS).join(", ")}`);
        process.exit(1);
      }
      await importVersion(version);
      await writeSearchIndex(version);
    }
    console.log("\n🎉 Import complete!");
    process.exit(0);
  } catch (err) {
    console.error("\n❌ Import failed:", err);
    process.exit(1);
  }
})();
