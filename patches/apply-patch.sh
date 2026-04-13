#!/bin/bash
# Anti-detection patch: inject human-like delay into qwen-mcp-tool

TARGET="/usr/local/lib/node_modules/qwen-mcp-tool/dist/tools/ask-qwen.tool.js"

# Write the patched file using cat with heredoc (avoids encoding issues)
cat > "$TARGET" << 'PATCHED_EOF'
import { z } from 'zod';
import { executeQwenCLI, processChangeModeOutput } from '../utils/qwenExecutor.js';
import { ERROR_MESSAGES, STATUS_MESSAGES } from '../constants.js';

function humanDelay() {
    const minDelay = 2000;
    const maxDelay = 8000;
    const delay = Math.floor(Math.random() * (maxDelay - minDelay + 1) + minDelay);
    return new Promise(resolve => setTimeout(resolve, delay));
}

const askQwenArgsSchema = z.object({
    prompt: z.string().min(1).describe("Analysis request. Use @ syntax to include files (e.g., '@largefile.js explain what this does') or ask general questions"),
    model: z.string().optional().describe("Optional model to use. If not specified, uses the default model."),
    sandbox: z.boolean().default(false).describe("Use sandbox mode (-s flag) to safely test code changes, execute scripts, or run potentially risky operations in an isolated environment"),
    changeMode: z.boolean().default(false).describe("Enable structured change mode - formats prompts to prevent tool errors and returns structured edit suggestions that Claude can apply directly"),
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
            return processChangeModeOutput('', chunkIndex, chunkCacheKey, prompt);
        }
        await humanDelay();
        const result = await executeQwenCLI(prompt, model, !!sandbox, !!changeMode, onProgress);
        if (changeMode) {
            return processChangeModeOutput(result, args.chunkIndex, undefined, prompt);
        }
        return STATUS_MESSAGES.QWEN_RESPONSE + "\n" + result;
    }
};
PATCHED_EOF

echo "Patched: $TARGET"
