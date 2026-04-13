#!/bin/bash
# Anti-detection patch: inject human-like delay into qwen-mcp-tool
set -e

TARGET="/usr/local/lib/node_modules/qwen-mcp-tool/dist/tools/ask-qwen.tool.js"

# Validate target exists
if [ ! -f "$TARGET" ]; then
    echo "✗ ERROR: Target file not found: $TARGET"
    echo "  qwen-mcp-tool version may have changed. Check npm package version."
    exit 1
fi

# Write the patched file using cat with heredoc
cat > "$TARGET" << 'PATCHED_EOF'
import { z } from 'zod';
import { executeQwenCLI, processChangeModeOutput } from '../utils/qwenExecutor.js';
import { ERROR_MESSAGES, STATUS_MESSAGES } from '../constants.js';

/**
 * Human-like delay with uniform random jitter (2-8 seconds).
 * Prevents pattern-based bot detection by introducing variable pauses.
 * Average ~5s delay = ~12 req/min (well within Qwen's 60 req/min limit).
 */
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
        try {
            // Human-like delay to prevent bot detection
            await humanDelay();
            const result = await executeQwenCLI(prompt, model, !!sandbox, !!changeMode, onProgress);
            if (changeMode) {
                return processChangeModeOutput(result, args.chunkIndex, undefined, prompt);
            }
            return STATUS_MESSAGES.QWEN_RESPONSE + "\n" + result;
        } catch (err) {
            throw new Error(`ask-qwen execution failed: ${err.message}`);
        }
    }
};
PATCHED_EOF

# Validate patch was applied
if ! grep -q "humanDelay" "$TARGET"; then
    echo "✗ ERROR: Patch validation failed — humanDelay not found in patched file"
    exit 1
fi

if ! grep -q "execution failed:" "$TARGET"; then
    echo "✗ ERROR: Error handling patch not applied"
    exit 1
fi

echo "✓ Anti-detection patch applied and validated: $TARGET"
