"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MODELS = void 0;
exports.getClaudeClient = getClaudeClient;
exports.studyLevelInstructions = studyLevelInstructions;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
let _client = null;
function getClaudeClient() {
    if (!_client) {
        const apiKey = process.env.ANTHROPIC_API_KEY;
        if (!apiKey)
            throw new Error("ANTHROPIC_API_KEY not set");
        _client = new sdk_1.default({ apiKey });
    }
    return _client;
}
exports.MODELS = {
    // Primary model for all real-time AI calls
    haiku: "claude-haiku-4-5",
};
function studyLevelInstructions(level) {
    return {
        beginner: "Use simple, clear language. Avoid theological jargon. Relate everything to everyday life. Keep explanations to 1-2 sentences.",
        growing: "Use accessible language with some theological terms explained. Include historical context briefly. 2-3 sentences per point.",
        scholar: "Use precise theological language. Include original language insights, historical context, and cross-references. Detailed analysis welcome.",
    }[level];
}
//# sourceMappingURL=client.js.map