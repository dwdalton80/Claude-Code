"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateSermonDebrief = generateSermonDebrief;
exports.suggestSermonTitle = suggestSermonTitle;
const client_1 = require("./client");
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
    const response = await client.messages.create({
        model: client_1.MODELS.haiku,
        max_tokens: 1000,
        messages: [
            {
                role: "user",
                content: `You are helping a user process and apply what they heard at church or studied in the Bible.

${ctx.sermonTitle ? `Sermon: "${ctx.sermonTitle}"` : ""}
${ctx.speaker ? `Speaker: ${ctx.speaker}` : ""}
${ctx.scriptureRefs.length ? `Scripture: ${ctx.scriptureRefs.join(", ")}` : ""}

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
    const json = text.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
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