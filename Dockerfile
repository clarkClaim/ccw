FROM node:20-bookworm

ARG TZ
ENV TZ="$TZ"
ARG GIT_DELTA_VERSION=0.18.2

# =============================================================================
# Layer 1: System tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Dev essentials
    git \
    less \
    sudo \
    fzf \
    zsh \
    man-db \
    unzip \
    gnupg2 \
    curl \
    wget \
    jq \
    # Editors
    vim \
    neovim \
    # Search
    ripgrep \
    # Terminal multiplexer
    tmux \
    # Firewall (for network isolation)
    iptables \
    ipset \
    iproute2 \
    dnsutils \
    aggregate \
    # SSH server (for remote access)
    openssh-server \
    # Build tools (for native node modules + psycopg2)
    build-essential \
    libpq-dev \
    # Python build deps (3.12 installed via uv below)
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    liblzma-dev \
    # Docker CLI (client only, no daemon)
    docker.io \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Git Delta (enhanced diffs)
RUN ARCH=$(dpkg --print-architecture) && \
    wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Starship prompt
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

# SSH server setup
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# =============================================================================
# Layer 2: Python toolchain (uv + global tools)
# =============================================================================
ENV UV_INSTALL_DIR="/usr/local/bin"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python 3.12 via uv and make it the default
RUN uv python install 3.12 && \
    ln -sf $(uv python find 3.12) /usr/local/bin/python3 && \
    ln -sf $(uv python find 3.12) /usr/local/bin/python

# Install Python tools globally via uv
RUN uv tool install ruff && \
    uv tool install basedpyright && \
    uv tool install just && \
    uv tool install pre-commit

# Add uv tool bin to PATH
ENV PATH="/root/.local/bin:$PATH"

# =============================================================================
# Layer 3: Node/TS toolchain
# =============================================================================
# Yarn (via corepack) for project-level package management
RUN corepack enable && corepack prepare yarn@stable --activate

# Global CLI tools (npm for global installs, yarn for projects)
RUN npm install -g \
    typescript \
    prisma \
    ts-node \
    nodemon \
    eslint \
    prettier


# =============================================================================
# Layer 4: User setup
# =============================================================================
# Create dev user with sudo
RUN useradd -m -s /bin/zsh -G sudo,docker dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev

# Set up directories
RUN mkdir -p /workspace /home/dev/.claude /home/dev/.claude-defaults /home/dev/.ssh && \
    chown -R dev:dev /workspace /home/dev

# Copy worker config (defaults kept separately since .claude may be a volume)
COPY worker-claude/.gitconfig /home/dev/.gitconfig
COPY worker-claude/CLAUDE.md /home/dev/.claude/CLAUDE.md
COPY worker-claude/settings.json /home/dev/.claude/settings.json
COPY worker-claude/CLAUDE.md /home/dev/.claude-defaults/CLAUDE.md
COPY worker-claude/settings.json /home/dev/.claude-defaults/settings.json

# Copy scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh && \
    echo "dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" >> /etc/sudoers.d/dev && \
    echo "dev ALL=(root) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers.d/dev

# Fix ownership
RUN chown -R dev:dev /home/dev

# Move uv tools to dev user
RUN cp -a /root/.local/bin/* /usr/local/bin/ 2>/dev/null || true && \
    chmod +x /usr/local/bin/ruff /usr/local/bin/basedpyright /usr/local/bin/just /usr/local/bin/pre-commit 2>/dev/null || true && \
    cp -a /root/.local/share/uv /home/dev/.local/share/uv 2>/dev/null || true && \
    chown -R dev:dev /home/dev/.local 2>/dev/null || true

USER dev
WORKDIR /workspace

# Persist command history
RUN mkdir -p /home/dev/.local/share && \
    touch /home/dev/.zsh_history

# Claude Code (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    sudo cp /home/dev/.local/bin/claude /usr/local/bin/claude && \
    sudo chmod +x /usr/local/bin/claude

# Shell prompt (Starship)
RUN echo 'eval "$(starship init zsh)"' >> /home/dev/.zshrc

ENV SHELL=/bin/zsh
ENV EDITOR=nvim
ENV VISUAL=nvim
ENV DEVCONTAINER=true

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
