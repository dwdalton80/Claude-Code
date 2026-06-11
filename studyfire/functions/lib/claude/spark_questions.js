"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateSparkQuestion = generateSparkQuestion;
const client_1 = require("./client");
/**
 * Generates a single observation-level question for Spark Mode.
 * Called once per passage at 2am daily — result cached in sparkcache/.
 * All free users share this cached question (cost-efficient).
 */
async function generateSparkQuestion(verseText, reference, version) {
    const client = (0, client_1.getClaudeClient)();
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 150,
        messages: [
            {
                role: "user",
                content: `You are generating a Bible study question for a mobile app designed for ages 16-30 with ADD-friendly design.

Passage: ${reference} (${version})
"${verseText}"

Write ONE simple observation question about this verse. Rules:
- Observation level only (what does the text SAY, not what it means)
- Simple language, no jargon
- Conversational and warm, not academic
- 15 words or less
- No wrong answers possible
- Examples: "What word stands out to you?" / "What does this verse say about God?" / "What action is described here?"

Respond with ONLY the question text, nothing else.`,
            },
        ],
    });
    const question = response.content[0].text.trim();
    return { question, verseText, reference };
}
//# sourceMappingURL=spark_questions.js.map