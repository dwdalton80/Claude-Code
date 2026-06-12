import Anthropic from "@anthropic-ai/sdk";

let _client: Anthropic | null = null;

export function getClaudeClient(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

export const MODELS = {
  // Primary model for all real-time AI calls
  haiku: "claude-haiku-4-5",
} as const;

export type StudyLevel = "beginner" | "growing" | "scholar";

export function studyLevelInstructions(level: StudyLevel): string {
  return {
    beginner:
      "Use simple, clear language. Avoid theological jargon. Relate everything to everyday life. Keep explanations to 1-2 sentences.",
    growing:
      "Use accessible language with some theological terms explained. Include historical context briefly. 2-3 sentences per point.",
    scholar:
      "Use precise theological language. Include original language insights, historical context, and cross-references. Detailed analysis welcome.",
  }[level];
}
