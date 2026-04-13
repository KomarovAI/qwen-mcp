FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    vim \
    less \
    openssh-client \
    python3 \
    python3-pip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Qwen Code CLI globally
RUN npm install -g @qwen-code/qwen-code

# Install MCP wrapper tools
RUN npm install -g qwen-mcp-tool supergateway

# Apply anti-detection patch: human-like delay between requests
COPY patches/apply-patch.sh /tmp/apply-patch.sh
RUN chmod +x /tmp/apply-patch.sh && /tmp/apply-patch.sh

# Create workspace directory
RUN mkdir -p /workspace

# Set working directory
WORKDIR /workspace

# Expose MCP server port
EXPOSE 9988

# Default: run supergateway with qwen-mcp-tool
CMD ["sh", "-c", "npx -y supergateway --stdio 'npx -y qwen-mcp-tool' --port 9988 --host 0.0.0.0"]
