import Anthropic from "@anthropic-ai/sdk";
import { getClaudeClient, MODELS } from "./client";

export type QuestionType =
  | "multiple_choice"
  | "true_false"
  | "fill_blank"
  | "passage_matching";

export interface QuizQuestion {
  type: QuestionType;
  question: string;
  options?: string[]; // for multiple_choice
  correctAnswer: string;
  explanation: string; // 1 sentence shown after answering
  topicTag: string;
  passageRef?: string;
  difficulty: "easy" | "medium" | "hard";
}

export interface DailyQuizCache {
  generatedAt: string; // ISO date
  questions: QuizQuestion[];
  topicTag: string;
}

/**
 * Generates daily quiz questions via Anthropic Batch API (50% cost savings).
 * Called nightly at 2am for each active topic tag.
 * Stored in dailycache/{date}/quizQuestions.
 */
export async function generateQuizBatch(
  topicTags: string[]
): Promise<Map<string, QuizQuestion[]>> {
  const client = getClaudeClient();

  // Build batch requests — one per topic tag
  const requests: Anthropic.MessageCreateParamsNonStreaming[] = topicTags.map((tag) => ({
    model: MODELS.haiku,
    max_tokens: 3000,
    messages: [
      {
        role: "user" as const,
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

  const results = new Map<string, QuizQuestion[]>();

  // Process results
  for await (const item of await client.beta.messages.batches.results(batch.id)) {
    if (item.result.type !== "succeeded") continue;

    const tag = item.custom_id.replace("quiz-", "");
    const text = (
      item.result.message.content[0] as { type: "text"; text: string }
    ).text.trim();

    try {
      const json = text.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
      const questions = JSON.parse(json) as QuizQuestion[];
      results.set(tag, questions);
    } catch {
      console.error(`Failed to parse quiz for tag ${tag}:`, text);
    }
  }

  return results;
}

function buildQuizPrompt(topicTag: string): string {
  return `You are generating Bible quiz questions for the topic: "${topicTag}".

Generate exactly 10 quiz questions about this topic from a evangelical Christian perspective.
Mix of types: at least 4 multiple_choice, 2 true_false, 2 fill_blank, 2 passage_matching.

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
export async function generateWordOfDay(
  passageText: string,
  reference: string,
  version: string
): Promise<WordOfDay> {
  const client = getClaudeClient();

  const response = await client.messages.create({
    model: MODELS.haiku,
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

  const text = (response.content[0] as { type: "text"; text: string }).text.trim();
  const json = text.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
  return JSON.parse(json) as WordOfDay;
}

export interface WordOfDay {
  word: string;
  originalWord: string;
  transliteration: string;
  pronunciation: string;
  strongsNumber: string;
  language: "greek" | "hebrew" | "aramaic";
  plainDefinition: string;
  funFact: string;
  otherPassages: string[];
  fromReference: string;
}
