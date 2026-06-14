"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateQuizBatch = generateQuizBatch;
exports.generateWordOfDay = generateWordOfDay;
const client_1 = require("./client");
/**
 * Generates daily quiz questions via Anthropic Batch API (50% cost savings).
 * Called nightly at 2am for each active topic tag.
 * Stored in dailycache/{date}/quizQuestions.
 */
async function generateQuizBatch(topicTags) {
    const client = (0, client_1.getClaudeClient)();
    // Build batch requests — one per topic tag
    const requests = topicTags.map((tag) => ({
        model: client_1.MODELS.haiku,
        max_tokens: 1500,
        messages: [
            {
                role: "user",
                content: buildQuizPrompt(tag),
            },
        ],
    }));
    // Use Batch API for 50% cost savings
    const batch = await client.beta.messages.batches.create({
        requests: requests.map((req, i) => ({
            custom_id: `quiz-${topicTags[i]}`,
            params: req,
        })),
    });
    // Poll for completion
    let batchResult = batch;
    while (batchResult.processing_status === "in_progress") {
        await new Promise((resolve) => setTimeout(resolve, 5000));
        batchResult = await client.beta.messages.batches.retrieve(batch.id);
    }
    const results = new Map();
    // Process results
    for await (const item of await client.beta.messages.batches.results(batch.id)) {
        if (item.result.type !== "succeeded")
            continue;
        const tag = item.custom_id.replace("quiz-", "");
        const text = item.result.message.content[0].text.trim();
        try {
            const json = text.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
            const questions = JSON.parse(json);
            results.set(tag, questions);
        }
        catch {
            console.error(`Failed to parse quiz for tag ${tag}:`, text);
        }
    }
    return results;
}
function buildQuizPrompt(topicTag) {
    return `You are generating Bible quiz questions for the topic: "${topicTag}".

Generate exactly 5 quiz questions about this topic from a evangelical Christian perspective.
Mix of types: at least 2 multiple_choice, 1 true_false, 1 fill_blank, 1 passage_matching.

Rules:
- Ages 16-30 audience
- Not too easy (avoid pop trivia) but not seminary-level
- Always reference specific Bible passages
- Explanations are warm and educational, never condescending
- Include a mix of difficulty levels

IMPORTANT: correctAnswer must be the FULL option string, matching one of the options exactly.

Return ONLY valid JSON array:
[
  {
    "type": "multiple_choice",
    "question": "...",
    "options": ["A. First option text", "B. Second option text", "C. Third option text", "D. Fourth option text"],
    "correctAnswer": "A. First option text",
    "explanation": "One sentence explanation of why this is correct.",
    "topicTag": "${topicTag}",
    "passageRef": "Romans 8:28",
    "difficulty": "medium"
  },
  ...
]`;
}
/**
 * Generates Word of the Day via Batch API — called nightly along with quiz.
 */
async function generateWordOfDay(passageText, reference, version) {
    const client = (0, client_1.getClaudeClient)();
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 400,
        messages: [
            {
                role: "user",
                content: `From this Bible passage, identify the single most theologically interesting word and explain it.

Passage: ${reference} (${version})
"${passageText}"

Pick a word that: has interesting original language meaning, reveals something surprising, or unlocks deeper understanding.

Return ONLY valid JSON:
{
  "word": "love",
  "originalWord": "ἀγάπη",
  "transliteration": "agape",
  "pronunciation": "ah-GAH-pay",
  "strongsNumber": "G26",
  "language": "greek",
  "plainDefinition": "Unconditional, self-giving love — not based on feelings but on choice.",
  "funFact": "2-3 sentence plain-English insight, fun-fact style. Example: The word for 'love' here is agape — not friendship love (phileo) or romantic love (eros), but a love that chooses to act regardless of how you feel.",
  "otherPassages": ["John 3:16", "1 Corinthians 13:4"],
  "fromReference": "${reference}"
}`,
            },
        ],
    });
    const text = response.content[0].text.trim();
    const json = text.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
    return JSON.parse(json);
}
//# sourceMappingURL=quiz_generation.js.map