#!/bin/bash
set -euo pipefail

# =============================================================================
# CCW Worker Entrypoint
# =============================================================================
# Modes (TASK_MODE env var):
#   existing  - Clone REPO_URL, create branch, run Claude on TASK_PROMPT
#   new       - Create new repo REPO_NAME, scaffold, run Claude on TASK_PROMPT
#   attach    - Start SSH + tmux, wait for user (no Claude)
# =============================================================================

TASK_MODE="${TASK_MODE:-existing}"
TASK_PROMPT="${TASK_PROMPT:-}"
REPO_URL="${REPO_URL:-}"
REPO_NAME="${REPO_NAME:-}"
MAX_TURNS="${MAX_TURNS:-50}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-false}"
BRANCH_PREFIX="${BRANCH_PREFIX:-claude}"

echo "=== CCW Worker Starting ==="
echo "Mode: $TASK_MODE"

# ---- SSH Server ----
# Host .ssh is mounted read-only at .ssh-mount; copy public keys to writable .ssh
if [ -d /home/dev/.ssh-mount ] && ls /home/dev/.ssh-mount/*.pub &>/dev/null; then
    mkdir -p /home/dev/.ssh
    cat /home/dev/.ssh-mount/*.pub > /home/dev/.ssh/authorized_keys 2>/dev/null || true
    chmod 700 /home/dev/.ssh
    chmod 600 /home/dev/.ssh/authorized_keys 2>/dev/null || true
    sudo /usr/sbin/sshd
    echo "SSH server started on port 22"
else
    echo "No SSH public keys found, skipping SSH server"
fi

# ---- Docker Socket ----
if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock
fi

# ---- Firewall ----
if [ "$ENABLE_FIREWALL" = "true" ]; then
    echo "Initializing firewall..."
    sudo /usr/local/bin/init-firewall.sh
fi

# ---- Git / GitHub Auth ----
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "Configuring GitHub authentication..."
    echo "https://oauth2:${GITHUB_TOKEN}@github.com" > /home/dev/.git-credentials
    chmod 600 /home/dev/.git-credentials
    git config --global credential.helper store

    # Auth gh CLI
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
fi

# ---- Task Slug ----
generate_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//'
}

# ---- Worker Config ----
# Volume mount may override baked-in config; ensure worker defaults exist
[ -f /home/dev/.claude/settings.json ] || cp /home/dev/.claude-defaults/settings.json /home/dev/.claude/settings.json
[ -f /home/dev/.claude/CLAUDE.md ] || cp /home/dev/.claude-defaults/CLAUDE.md /home/dev/.claude/CLAUDE.md

# ---- Claude Code Auth ----
# Check if Claude is already authed; if not, run interactive login
if ! claude auth status &>/dev/null; then
    echo ""
    echo "========================================"
    echo "  Claude Code login required"
    echo "  A browser URL will be shown below."
    echo "  Copy it to your host browser to auth."
    echo "========================================"
    echo ""
    claude login
fi

# =============================================================================
# Mode: local (copy in project files, run Claude interactively)
# =============================================================================
if [ "$TASK_MODE" = "local" ]; then
    mkdir -p /workspace/repo
    cd /workspace/repo
    tar xzf /tmp/src.tar.gz

    # Init git if not already a repo
    if [ ! -d .git ]; then
        git init
        git add -A
        git commit -m "initial import" --allow-empty
    fi

    if [ -n "$TASK_PROMPT" ]; then
        exec claude -p "$TASK_PROMPT" --dangerously-skip-permissions
    else
        exec claude --dangerously-skip-permissions
    fi
fi

# =============================================================================
# Mode: attach (just start tmux and wait)
# =============================================================================
if [ "$TASK_MODE" = "attach" ]; then
    echo "Attach mode -- starting tmux session"
    exec tmux new-session -s worker
fi

# =============================================================================
# Mode: existing (clone repo, branch, work)
# =============================================================================
if [ "$TASK_MODE" = "existing" ]; then
    if [ -z "$REPO_URL" ]; then
        echo "ERROR: REPO_URL required for 'existing' mode"
        exit 1
    fi
    if [ -z "$TASK_PROMPT" ]; then
        echo "ERROR: TASK_PROMPT required"
        exit 1
    fi

    SLUG=$(generate_slug "$TASK_PROMPT")
    BRANCH="${BRANCH_PREFIX}/${SLUG}"

    echo "Cloning $REPO_URL ..."
    git clone "$REPO_URL" /workspace/repo
    cd /workspace/repo

    echo "Creating branch: $BRANCH"
    git checkout -b "$BRANCH"

    # Copy worker CLAUDE.md if repo doesn't have one
    if [ ! -f CLAUDE.md ]; then
        cp /home/dev/.claude/CLAUDE.md ./CLAUDE.md
        echo "(Worker CLAUDE.md copied into repo)"
    fi
fi

# =============================================================================
# Mode: new (create repo, scaffold, work)
# =============================================================================
if [ "$TASK_MODE" = "new" ]; then
    if [ -z "$REPO_NAME" ]; then
        echo "ERROR: REPO_NAME required for 'new' mode"
        exit 1
    fi
    if [ -z "$TASK_PROMPT" ]; then
        echo "ERROR: TASK_PROMPT required"
        exit 1
    fi

    SLUG=$(generate_slug "$TASK_PROMPT")
    BRANCH="${BRANCH_PREFIX}/${SLUG}"

    echo "Creating new repo: $REPO_NAME"
    mkdir -p /workspace/repo
    cd /workspace/repo
    git init

    # Copy worker CLAUDE.md
    cp /home/dev/.claude/CLAUDE.md ./CLAUDE.md

    # Initial commit
    git add CLAUDE.md
    git commit -m "feat: initial project setup"

    # Create GitHub repo (private by default)
    gh repo create "$REPO_NAME" --private --source=. --push 2>/dev/null || {
        echo "WARNING: Could not create GitHub repo (may already exist or gh not authed)"
    }

    echo "Creating branch: $BRANCH"
    git checkout -b "$BRANCH"
fi

# =============================================================================
# Run Claude Code
# =============================================================================
echo ""
echo "=== Starting Claude Code ==="
echo "Branch: $(git branch --show-current)"
echo "Prompt: $TASK_PROMPT"
echo "Max turns: $MAX_TURNS"
echo ""

# Run Claude in a tmux session so we can attach later
tmux new-session -d -s worker -c /workspace/repo \
    "claude -p \"$TASK_PROMPT\" \
        --dangerously-skip-permissions \
        --max-turns $MAX_TURNS \
        --output-format stream-json \
    2>&1 | tee /workspace/claude-output.log; \
    echo ''; \
    echo '=== Claude Code finished ==='; \
    echo 'Container staying alive for inspection. Exit tmux to stop.'; \
    exec zsh"

echo "Claude running in tmux session 'worker'"
echo "  Attach: tmux attach -t worker"
echo "  Logs:   tail -f /workspace/claude-output.log"

# Keep container alive
exec tail -f /dev/null
