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
exports.generateSermonDebrief = generateSermonDebrief;
exports.suggestSermonTitle = suggestSermonTitle;
const admin = __importStar(require("firebase-admin"));
const client_1 = require("./client");
const db = () => admin.firestore();
/**
 * Maps common Bible book names (and abbreviations) to the Firestore document IDs
 * used under bible/kjv/books/{bookId}. Must match the IDs used by the Flutter
 * client's _bookIds map in reader_screen.dart.
 */
const BOOK_ID_MAP = {
    // Old Testament
    "genesis": "gen", "gen": "gen",
    "exodus": "exo", "exo": "exo",
    "leviticus": "lev", "lev": "lev",
    "numbers": "num", "num": "num",
    "deuteronomy": "deu", "deu": "deu",
    "joshua": "jos", "jos": "jos",
    "judges": "jdg", "jdg": "jdg",
    "ruth": "rut", "rut": "rut",
    "1 samuel": "1sa", "1samuel": "1sa", "1sa": "1sa",
    "2 samuel": "2sa", "2samuel": "2sa", "2sa": "2sa",
    "1 kings": "1ki", "1kings": "1ki", "1ki": "1ki",
    "2 kings": "2ki", "2kings": "2ki", "2ki": "2ki",
    "1 chronicles": "1ch", "1chronicles": "1ch", "1ch": "1ch",
    "2 chronicles": "2ch", "2chronicles": "2ch", "2ch": "2ch",
    "ezra": "ezr", "ezr": "ezr",
    "nehemiah": "neh", "neh": "neh",
    "esther": "est", "est": "est",
    "job": "job",
    "psalms": "psa", "psalm": "psa", "psa": "psa", "ps": "psa",
    "proverbs": "pro", "pro": "pro",
    "ecclesiastes": "ecc", "ecc": "ecc",
    "song of solomon": "sng", "song of songs": "sng", "sng": "sng",
    "isaiah": "isa", "isa": "isa",
    "jeremiah": "jer", "jer": "jer",
    "lamentations": "lam", "lam": "lam",
    "ezekiel": "eze", "eze": "eze",
    "daniel": "dan", "dan": "dan",
    "hosea": "hos", "hos": "hos",
    "joel": "jol", "jol": "jol",
    "amos": "amo", "amo": "amo",
    "obadiah": "oba", "oba": "oba",
    "jonah": "jon", "jon": "jon",
    "micah": "mic", "mic": "mic",
    "nahum": "nam", "nam": "nam",
    "habakkuk": "hab", "hab": "hab",
    "zephaniah": "zep", "zep": "zep",
    "haggai": "hag", "hag": "hag",
    "zechariah": "zec", "zec": "zec",
    "malachi": "mal", "mal": "mal",
    // New Testament
    "matthew": "mat", "matt": "mat", "mat": "mat",
    "mark": "mrk", "mrk": "mrk",
    "luke": "luk", "luk": "luk",
    "john": "jhn", "jhn": "jhn",
    "acts": "act", "act": "act",
    "romans": "rom", "rom": "rom",
    "1 corinthians": "1co", "1corinthians": "1co", "1co": "1co",
    "2 corinthians": "2co", "2corinthians": "2co", "2co": "2co",
    "galatians": "gal", "gal": "gal",
    "ephesians": "eph", "eph": "eph",
    "philippians": "php", "php": "php",
    "colossians": "col", "col": "col",
    "1 thessalonians": "1th", "1thessalonians": "1th", "1th": "1th",
    "2 thessalonians": "2th", "2thessalonians": "2th", "2th": "2th",
    "1 timothy": "1ti", "1timothy": "1ti", "1ti": "1ti",
    "2 timothy": "2ti", "2timothy": "2ti", "2ti": "2ti",
    "titus": "tit", "tit": "tit",
    "philemon": "phm", "phm": "phm",
    "hebrews": "heb", "heb": "heb",
    "james": "jas", "jas": "jas",
    "1 peter": "1pe", "1peter": "1pe", "1pe": "1pe",
    "2 peter": "2pe", "2peter": "2pe", "2pe": "2pe",
    "1 john": "1jn", "1john": "1jn", "1jn": "1jn",
    "2 john": "2jn", "2john": "2jn", "2jn": "2jn",
    "3 john": "3jn", "3john": "3jn", "3jn": "3jn",
    "jude": "jud", "jud": "jud",
    "revelation": "rev", "rev": "rev",
};
/**
 * Fetches verse text from Firestore for a human-readable reference like "John 3:16".
 * Returns null if lookup fails — debrief still works without it.
 */
async function fetchVerseText(ref) {
    try {
        // Normalise: "John 3:16" → book=jhn, chapter=3, verse=16
        const match = ref.trim().match(/^(.+?)\s+(\d+):(\d+)(?:-(\d+))?$/);
        if (!match)
            return null;
        const bookKey = match[1].toLowerCase().trim();
        const bookId = BOOK_ID_MAP[bookKey];
        if (!bookId)
            return null; // unknown book name
        const chapter = parseInt(match[2], 10);
        const verseStart = parseInt(match[3], 10);
        const verseEnd = match[4] ? parseInt(match[4], 10) : verseStart;
        const snap = await db()
            .collection("bible").doc("kjv")
            .collection("books").doc(bookId)
            .collection("chapters").doc(String(chapter))
            .collection("verses")
            .where("verseNumber", ">=", verseStart)
            .where("verseNumber", "<=", verseEnd)
            .orderBy("verseNumber")
            .get();
        if (snap.empty)
            return null;
        return snap.docs.map(d => d.data().text ?? d.data().verseText ?? "").join(" ").trim();
    }
    catch {
        return null;
    }
}
/**
 * "Unpack This" AI Debrief for journal notes.
 * Free: 1/month. Premium: unlimited.
 * If notes < 50 words, caller must collect follow-up answers first.
 */
async function generateSermonDebrief(ctx) {
    const client = (0, client_1.getClaudeClient)();
    const levelInstructions = (0, client_1.studyLevelInstructions)(ctx.studyLevel);
    const additionalContext = ctx.followUpAnswers?.length
        ? `\n\nAdditional context from the user:\n${ctx.followUpAnswers.join("\n")}`
        : "";
    // Pre-fetch verse texts for any scripture refs the user tagged
    let scriptureBlock = "";
    if (ctx.scriptureRefs.length > 0) {
        const fetched = await Promise.all(ctx.scriptureRefs.map(async (ref) => {
            const text = await fetchVerseText(ref);
            return text ? `${ref}: "${text}"` : ref;
        }));
        scriptureBlock = `\nScripture texts:\n${fetched.join("\n")}`;
    }
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 1000,
        system: "You are a Bible study assistant. You ALWAYS respond with valid JSON only. Never include any text outside the JSON object. Never explain or add commentary.",
        messages: [
            {
                role: "user",
                content: `A user is studying the Bible and needs help processing their notes. Return ONLY a JSON object with no other text.

You are helping a user process and apply what they heard at church or studied in the Bible.

${ctx.sermonTitle ? `Sermon: "${ctx.sermonTitle}"` : ""}
${ctx.speaker ? `Speaker: ${ctx.speaker}` : ""}
${scriptureBlock || (ctx.scriptureRefs.length ? `Scripture: ${ctx.scriptureRefs.join(", ")}` : "")}

User's notes:
"${ctx.noteContent}"${additionalContext}

STYLE: ${levelInstructions}
TONE: Warm, pastoral, practical. Never preachy. Focus on real-life application.
AUDIENCE: Christian ages 16-30. They want to LIVE this, not just know it.

Return ONLY valid JSON:
{
  "applicationPoints": [
    {"id": "uuid1", "text": "Specific, actionable step they can take this week"},
    {"id": "uuid2", "text": "..."},
    {"id": "uuid3", "text": "..."}
  ],
  "discussionQuestions": [
    "Question 1 (good for small group)",
    "Question 2",
    "Question 3",
    "Question 4",
    "Question 5"
  ],
  "bigIdea": "Single sentence capturing the core message",
  "followUpScripture": ["Romans 12:1-2", "James 1:22"],
  "personalChallenge": "One specific, concrete action they can do TODAY or this week"
}

Application points must be:
- Specific (not "pray more" but "spend 5 minutes thanking God before checking your phone tomorrow morning")
- Doable within 1 week
- Tied to what they actually wrote`,
            },
        ],
    });
    const text = response.content[0].text.trim();
    // Extract JSON - handle markdown code blocks and extra text
    let json = text;
    const codeBlockMatch = text.match(/```(?:json)?\n?([\s\S]*?)\n?```/);
    if (codeBlockMatch) {
        json = codeBlockMatch[1].trim();
    }
    else {
        // Find first { and last } to extract JSON object
        const start = text.indexOf("{");
        const end = text.lastIndexOf("}");
        if (start !== -1 && end !== -1) {
            json = text.substring(start, end + 1);
        }
    }
    return JSON.parse(json);
}
/**
 * AI auto-suggests a sermon title when the note is saved without one.
 */
async function suggestSermonTitle(noteContent) {
    const client = (0, client_1.getClaudeClient)();
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 60,
        messages: [
            {
                role: "user",
                content: `Based on these sermon notes, suggest a brief, catchy sermon title (5-8 words max).

Notes: "${noteContent.slice(0, 500)}"

Respond with ONLY the title, no quotes, no explanation.`,
            },
        ],
    });
    return response.content[0].text.trim();
}
//# sourceMappingURL=sermon_debrief.js.map