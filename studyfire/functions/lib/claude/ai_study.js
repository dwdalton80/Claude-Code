"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateAiStudy = generateAiStudy;
const client_1 = require("./client");
/**
 * Generates a full AI study session for a passage.
 * Called per Premium user when they tap "Ask AI" or "Go Deeper".
 * Returns structured JSON cached in Firestore after first call.
 */
async function generateAiStudy(ctx) {
    const client = (0, client_1.getClaudeClient)();
    const levelInstructions = (0, client_1.studyLevelInstructions)(ctx.studyLevel);
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 1200,
        messages: [
            {
                role: "user",
                content: `You are StudyFire's AI Bible study guide. Generate a structured study session for the following passage.

PASSAGE: ${ctx.reference} (${ctx.version})
"${ctx.passageText}"

USER PROFILE:
- Study level: ${ctx.studyLevel}
- Goal: ${ctx.studyGoal}
- Recent weak topics: ${ctx.recentQuizHistory.join(", ") || "none"}

STYLE INSTRUCTIONS: ${levelInstructions}
DESIGN RULE: ADD-friendly. Short, punchy. One idea per point. Never intimidating. Warm and encouraging tone.

Return ONLY valid JSON with this exact structure:
{
  "questions": ["question1", "question2", "question3", "question4", "question5"],
  "contextBrief": "1 paragraph historical/cultural context (3-4 sentences max)",
  "tldr": "Single sentence TL;DR of the context",
  "themes": ["theme1", "theme2"],
  "crossRefs": ["Book 1:1", "Book 2:3"],
  "characterSpotlight": "Brief note if a named person appears, else null",
  "devotionalPrompt": "One personal reflection question"
}

Questions must be:
- Progressive in depth (not all the same type)
- Mix: observation, interpretation, application, personal reflection, one bold/creative
- Short (under 20 words each)
- No wrong answers
- Warm, conversational tone`,
            },
        ],
    });
    const raw = response.content[0].text.trim();
    // Strip markdown code fences if present
    const json = raw.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
    return JSON.parse(json);
}
//# sourceMappingURL=ai_study.js.map