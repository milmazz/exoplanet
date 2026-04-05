FROM elixir:1.18-slim

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    nodejs \
    npm \
    iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Claude CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user (container starts as root so entrypoint can configure iptables;
# VS Code connects as this user via remoteUser in devcontainer.json)
RUN groupadd -r elixir && useradd -m -d /home/elixir -g elixir -u 1000 elixir

WORKDIR /workspace

CMD ["/bin/bash"]
