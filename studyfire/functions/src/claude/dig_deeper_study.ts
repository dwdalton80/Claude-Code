import { getClaudeClient, MODELS } from "./client";

export interface DigDeeperStudyRequest {
  bookId: string;
  bookName: string;
  chapter: number;
  version: string;
  method: string; // 'soap' | 'inductive' | 'swedish' | 'lectioDivina' | 'wordStudy'
  passageText: string;
  recentStudies?: Array<{ bookName: string; chapter: number; method: string }>;
}

export interface DigDeeperStudyResponse {
  overview: string;
  observations: string[];
  interpretation: string;
  applicationPoints: string[];
  reflectionQuestions: string[];
  prayerPrompt: string;
  commentary?: string;
}

const METHOD_INSTRUCTIONS: Record<string, string> = {
  soap: `Use the SOAP method:
- overview: 1-2 sentence summary of the passage
- observations: 4 things the text literally says (short, factual)
- interpretation: 1 paragraph — what does this mean theologically?
- applicationPoints: 3 practical "I will..." statements for modern life
- reflectionQuestions: 3 personal reflection questions
- prayerPrompt: 1-2 sentence prayer prompt based on the passage`,

  inductive: `Use the Inductive method (Observe → Interpret → Apply):
- overview: Brief context of the passage (2-3 sentences)
- observations: 4 things you notice in the text (facts, repetitions, contrasts)
- interpretation: What do these observations mean? (1 paragraph)
- applicationPoints: 3 ways to apply this truth
- reflectionQuestions: 3 questions to ponder
- prayerPrompt: A short closing prayer prompt`,

  swedish: `Use the Swedish method (Arrow = convicts, Question mark = confuses, Candle = inspires others):
- overview: 1-2 sentence intro to the passage
- observations: 3 things that stand out (arrows hitting the heart, candles of insight)
- interpretation: 1 paragraph unpacking the main message
- applicationPoints: 3 ways to live this out or share it
- reflectionQuestions: 3 questions — one personal conviction, one you'd ask, one to share with someone
- prayerPrompt: A prayer of response to what spoke to you`,

  lectioDivina: `Use Lectio Divina (Read → Meditate → Pray → Contemplate):
- overview: Set the scene — historical and spiritual context (2-3 sentences)
- observations: 3 words or phrases that stand out for meditation
- interpretation: 1 paragraph — what is God saying through this text?
- applicationPoints: 3 ways to rest and respond to this truth (not just "do" items)
- reflectionQuestions: 3 contemplative questions for slow meditation
- prayerPrompt: A contemplative prayer prompt — listen as much as speak`,

  wordStudy: `Do an original language word study on this passage:
- overview: 1-2 sentence introduction to what this chapter is about
- observations: 4 KEY WORDS from the passage — for each, provide: the English word, its original Greek or Hebrew word (transliterated), its Strong's meaning, and why it matters for understanding this text. Format each as: "[English word] (Greek/Hebrew: [transliteration]) — [meaning and significance]"
- interpretation: 1 paragraph — how do these original meanings deepen or change the way a modern reader understands this passage?
- applicationPoints: 3 ways this richer word-level understanding changes how you live or pray
- reflectionQuestions: 3 questions that arise from the original language meanings
- prayerPrompt: A prayer that uses the depth of the original words to speak back to God`,
};

export async function generateDigDeeperStudy(
  req: DigDeeperStudyRequest
): Promise<DigDeeperStudyResponse> {
  const client = getClaudeClient();
  const methodInstr = METHOD_INSTRUCTIONS[req.method] ?? METHOD_INSTRUCTIONS.inductive;

  // Static system prompt — cached by Anthropic after first use (saves ~90% on input tokens)
  const systemPrompt = `You are a Bible study guide for Dig Deeper, a thoughtful app for Christian young adults.

TONE: Warm, accessible, encouraging. Not preachy. Speak to someone who genuinely wants to grow.

Return ONLY valid JSON with this exact structure (no markdown, no explanation):
{
  "overview": "string",
  "observations": ["string", "string", "string", "string"],
  "interpretation": "string",
  "applicationPoints": ["string", "string", "string"],
  "reflectionQuestions": ["string", "string", "string"],
  "prayerPrompt": "string",
  "commentary": "string"
}

For "commentary": Write 2-3 sentences synthesizing what one or two classic Bible commentators (Calvin, Spurgeon, or Matthew Henry) said about this passage's central theme. Make it accessible and illuminating — one meaningful insight, not a quote dump. Name the commentator(s) you draw from.`;

  const historyContext =
    req.recentStudies && req.recentStudies.length > 0
      ? `\n\nUSER'S RECENT STUDIES: ${req.recentStudies
          .map((s) => `${s.bookName} ${s.chapter} (${s.method})`)
          .join("; ")}. Where it fits naturally, you may draw a brief connection to their recent journey — but only if genuinely relevant.`
      : "";

  const userPrompt = `PASSAGE: ${req.bookName} ${req.chapter} (${req.version.toUpperCase()})
"${req.passageText}"

STUDY METHOD: ${req.method.toUpperCase()}
${methodInstr}${historyContext}`;

  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 1800,
    system: [
      {
        type: "text",
        text: systemPrompt,
        cache_control: { type: "ephemeral" },
      },
    ],
    messages: [{ role: "user", content: userPrompt }],
  });

  const raw = (response.content[0] as { type: "text"; text: string }).text.trim();
  const json = raw.replace(/^```json\n?/, "").replace(/\n?```$/, "").trim();
  const start = json.indexOf("{");
  const end = json.lastIndexOf("}");
  return JSON.parse(json.substring(start, end + 1)) as DigDeeperStudyResponse;
}

export async function askDigDeeperQuestion(
  question: string,
  passage: string,
  passageText: string,
  history: Array<{ role: string; content: string }>
): Promise<string> {
  const client = getClaudeClient();

  const messages: Array<{ role: "user" | "assistant"; content: string }> = [
    ...history
      .slice(-6)
      .map((m) => ({ role: m.role as "user" | "assistant", content: m.content })),
    {
      role: "user",
      content: question,
    },
  ];

  const response = await client.messages.create({
    model: MODELS.haiku,
    max_tokens: 500,
    system: `You are a Bible study guide for Dig Deeper. The user is studying ${passage}.
Passage text: "${passageText.substring(0, 800)}"

Answer ONLY questions related to the Bible, biblical theology, Christian faith, prayer, or the passage above. If the user asks about anything outside of these topics, politely decline and redirect them to the passage or a related biblical question. Keep answers to 2-4 sentences. Be warm, not preachy. If unsure of an answer, say so humbly.`,
    messages,
  });

  return (response.content[0] as { type: "text"; text: string }).text.trim();
}
