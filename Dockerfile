FROM node:20-slim

# Install minimal runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    openssh-client \
    python3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install pinned versions of all packages
RUN npm install -g \
    @qwen-code/qwen-code@0.14.4 \
    qwen-mcp-tool@0.1.0 \
    supergateway@1.3.0

# Apply anti-detection patch: human-like delay between requests
COPY patches/apply-patch.sh /tmp/apply-patch.sh
RUN chmod +x /tmp/apply-patch.sh && /tmp/apply-patch.sh

# Validate patch was applied
RUN grep -q "humanDelay" /usr/local/lib/node_modules/qwen-mcp-tool/dist/tools/ask-qwen.tool.js \
    && echo "✓ Anti-detection patch applied successfully" \
    || { echo "✗ Patch validation failed!"; exit 1; }

# Create workspace directory
RUN mkdir -p /workspace && chown node:node /workspace

# Set working directory
WORKDIR /workspace

# Run as non-root user
USER node

# Expose MCP server port
EXPOSE 9988

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:9988/sse > /dev/null 2>&1 || exit 1

# Run supergateway with qwen-mcp-tool (use explicit paths, not npx)
CMD ["sh", "-c", "supergateway --stdio 'qwen-mcp-tool' --port 9988 --host 0.0.0.0"]
