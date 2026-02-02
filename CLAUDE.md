# CCW - Claude Code Worker

## What This Is

A CLI tool + Docker image that spawns isolated containers running Claude Code in YOLO mode. Work is tracked as GitHub branches and PRs. The user dispatches tasks from their local machine; containers run on their local Docker.

## Project Structure

```
ccw/
├── Dockerfile                  # Fat image: Node 20 + Python 3.11 + full toolchain
├── init-firewall.sh            # iptables network isolation (Anthropic-based)
├── entrypoint.sh               # Clone/create repo, branch, run Claude, push PRs
├── docker-compose.yml          # Worker + sibling DBs (Qdrant, Postgres, ClickHouse)
├── ccw                         # Bash CLI launcher
├── .env.example                # Credential template (never commit .env)
├── .gitignore
├── README.md
├── CLAUDE.md                   # This file
└── worker-claude/              # Config baked into the Docker image
    ├── CLAUDE.md               # Instructions for the agent running INSIDE the container
    ├── settings.json           # Deny patterns for secrets
    └── .gitconfig              # Git identity (Joshua Clark)
```

## Key Distinction

There are TWO CLAUDE.md files:
- **This file** (`/ccw/CLAUDE.md`): For working on the ccw project itself
- **`/ccw/worker-claude/CLAUDE.md`**: Baked into the Docker image, read by the Claude Code agent running inside a worker container

## Development

```bash
# Build the image after changes
./ccw build

# Test interactively
./ccw shell

# Test a real task (use a throwaway repo)
./ccw run https://github.com/user/test-repo "Add a hello world endpoint"

# List / attach / kill workers
./ccw ls
./ccw attach <name>
./ccw kill <name>
```

After changing the Dockerfile or any file in `worker-claude/`, rebuild with `./ccw build`.

After changing `ccw`, `entrypoint.sh`, or `init-firewall.sh`, rebuild is also needed since those are COPYed into the image.

## Publishing

Image is published to GitHub Container Registry:

```bash
docker tag ccw-worker ghcr.io/clarkclaim/ccw-worker:latest
docker push ghcr.io/clarkclaim/ccw-worker:latest
```

## Architecture Decisions

- **One fat image** with both Python and Node/TS toolchains (~4-5GB). Pre-warmed so Claude doesn't waste turns installing tools.
- **Credentials injected at runtime** via env vars and volume mounts. Never baked into image.
- **Firewall optional** (`--firewall` flag). Whitelists GitHub, npm, PyPI, Anthropic API, OpenAI, HuggingFace, Modal. Blocks everything else.
- **SSH server** in the container so user can SSH in or mount via SSHFS for visual editing.
- **tmux** session inside container -- Claude runs in it, user can attach to watch or interact.
- **Sibling databases** (Postgres, Qdrant, ClickHouse) are in docker-compose.yml, commented out by default.
- **Docker socket mounted** so the worker container can talk to sibling containers on the host.

## User Profile

- **Owner**: Joshua Clark (josh@clarkpdx.com)
- **Python stack**: uv, ruff, basedpyright, pytest, just, pre-commit, pydantic
- **Node stack**: TypeScript, Prisma, Apollo/GraphQL, React, Vite, Jest, ESLint, Prettier
- **Preferences**: conventional commits, feature branches, PRs for review, spec-driven development
