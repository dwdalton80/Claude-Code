import { getClaudeClient, MODELS, StudyLevel, studyLevelInstructions } from "./client";

export interface SermonDebrief {
  applicationPoints: ApplicationPoint[];
  discussionQuestions: string[];
  bigIdea: string;
  followUpScripture: string[];
  personalChallenge: string;
}

export interface ApplicationPoint {
  id: string;
  text: string;
}

export interface DebriefContext {
  noteContent: string;
  sermonTitle?: string;
  speaker?: string;
  scriptureRefs: string[];
  studyLevel: StudyLevel;
  followUpAnswers?: string[]; // answers to the 2 follow-up prompts for short notes
}

/**
 * "Unpack This" AI Debrief for journal notes.
 * Free: 1/month. Premium: unlimited.
 * If notes < 50 words, caller must collect follow-up answers first.
 */
export async function generateSermonDebrief(ctx: DebriefContext): Promise<SermonDebrief> {
  const client = getClaudeClient();

  const levelInstructions = studyLevelInstructions(ctx.studyLevel);
  const additionalContext = ctx.followUpAnswers?.length
    ? `\n\nAdditional context from the user:\n${ctx.followUpAnswers.join("\n")}`
    : "";

  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 1000,
    system: "You are a Bible study assistant. You ALWAYS respond with valid JSON only. Never include any text outside the JSON object. Never explain or add commentary.",
    messages: [
      {
        role: "user",
        content: `A user is studying the Bible and needs help processing their notes. Return ONLY a JSON object with no other text.

You are helping a user process and apply what they heard at church or studied in the Bible.

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

  const text = (response.content[0] as { type: "text"; text: string }).text.trim();
  // Extract JSON - handle markdown code blocks and extra text
  let json = text;
  const codeBlockMatch = text.match(/```(?:json)?\n?([\s\S]*?)\n?```/);
  if (codeBlockMatch) {
    json = codeBlockMatch[1].trim();
  } else {
    // Find first { and last } to extract JSON object
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start !== -1 && end !== -1) {
      json = text.substring(start, end + 1);
    }
  }
  return JSON.parse(json) as SermonDebrief;
}

/**
 * AI auto-suggests a sermon title when the note is saved without one.
 */
export async function suggestSermonTitle(noteContent: string): Promise<string> {
  const client = getClaudeClient();

  const response = await client.messages.create({
    model: MODELS.haiku,
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

  return (response.content[0] as { type: "text"; text: string }).text.trim();
}
