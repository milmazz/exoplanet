FROM elixir:1.18-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    nodejs \
    npm \
    iptables \
    ipset \
    dnsutils \
    curl \
    fish \
    vim-tiny \
    locales \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Install Claude CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user (container starts as root so entrypoint can configure iptables;
# VS Code connects as this user via remoteUser in devcontainer.json)
RUN groupadd -r elixir && useradd -m -d /home/elixir -g elixir -u 1000 -s /usr/bin/fish elixir

WORKDIR /workspace

CMD ["/bin/bash"]
