import { z } from 'zod';
import { executeQwenCLI, processChangeModeOutput } from '../utils/qwenExecutor.js';
import { ERROR_MESSAGES, STATUS_MESSAGES } from '../constants.js';

/**
 * Human-like rate limiting with jitter.
 * Prevents detection by adding variable delays (2-8 seconds) between requests.
 * - Min 2s, max 8s delay (average ~5s = ~12 req/min)
 * - Qwen free tier: 100 req/day, 60 req/min — we stay well within limits
 */
function humanDelay() {
    const minDelay = 2000;  // 2 seconds
    const maxDelay = 8000;  // 8 seconds
    const delay = Math.floor(Math.random() * (maxDelay - minDelay + 1) + minDelay);
    return new Promise(resolve => setTimeout(resolve, delay));
}

const askQwenArgsSchema = z.object({
    prompt: z.string().min(1).describe("Analysis request. Use @ syntax to include files (e.g., '@largefile.js explain what this does') or ask general questions"),
    model: z.string().optional().describe("Optional model to use. If not specified, uses the default model."),
    sandbox: z.boolean().default(false).describe("Use sandbox mode (-s flag) to safely test code changes, execute scripts, or run potentially risky operations in an isol
ated environment"),
    changeMode: z.boolean().default(false).describe("Enable structured change mode - formats prompts to prevent tool errors and returns structured edit suggestions that 
Claude can apply directly"),
    chunkIndex: z.union([z.number(), z.string()]).optional().describe("Which chunk to return (1-based)"),
    chunkCacheKey: z.string().optional().describe("Optional cache key for continuation"),
});

export const askQwenTool = {
    name: "ask-qwen",
    description: "model selection [-m], sandbox [-s], and changeMode:boolean for providing edits",
    zodSchema: askQwenArgsSchema,
    prompt: {
        description: "Execute 'qwen -p <prompt>' to get qwen AI's response. Supports enhanced change mode for structured edit suggestions.",
    },
    category: 'qwen',
    execute: async (args, onProgress) => {
        const { prompt, model, sandbox, changeMode, chunkIndex, chunkCacheKey } = args;
        if (!prompt?.trim()) {
            throw new Error(ERROR_MESSAGES.NO_PROMPT_PROVIDED);
        }
        if (changeMode && chunkIndex && chunkCacheKey) {
            return processChangeModeOutput('', // empty for cache...
            chunkIndex, chunkCacheKey, prompt);
        }

        // Add human-like delay before executing
        await humanDelay();

        const result = await executeQwenCLI(prompt, model, !!sandbox, !!changeMode, onProgress);
        if (changeMode) {
            return processChangeModeOutput(result, args.chunkIndex, undefined, prompt);
        }
        return `${STATUS_MESSAGES.QWEN_RESPONSE}\n${result}`; // changeMode false
    }
};
