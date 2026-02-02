# CCW - Claude Code Worker

Spawn isolated Docker containers that run Claude Code in YOLO mode with your full toolchain. Work is tracked as GitHub branches and PRs.

## Quick Start

```bash
# 1. Build the image
./ccw build

# 2. Configure credentials
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY and GITHUB_TOKEN

# 3. Run a task on an existing repo
./ccw run https://github.com/you/repo "Add user authentication with JWT"

# 4. Or create a new project
./ccw new my-api "Create a FastAPI project with CRUD endpoints and tests"
```

## Commands

| Command | Description |
|---------|-------------|
| `ccw build` | Build the Docker image |
| `ccw run <url> "<prompt>"` | Clone repo, branch, run Claude, push PR |
| `ccw new <name> "<prompt>"` | Create new repo, scaffold, run Claude |
| `ccw shell` | Interactive shell in a fresh container |
| `ccw attach <name>` | tmux attach to running worker |
| `ccw ssh <name>` | SSH into running worker |
| `ccw exec <name> "cmd"` | Run a command in a worker |
| `ccw ls` | List running workers |
| `ccw logs <name>` | Tail Claude's output |
| `ccw kill <name>` | Stop and remove a worker |
| `ccw kill-all` | Stop all workers |

## Options

| Flag | Description |
|------|-------------|
| `--firewall` | Enable network restrictions (whitelist only) |
| `--max-turns N` | Max Claude turns (default: 50) |
| `--ssh-port PORT` | Specific SSH port (default: auto) |
| `--follow` | Tail logs after starting |

## What's in the Container

**Runtimes:** Node.js 20, Python 3.11, TypeScript 5

**Python:** uv, ruff, basedpyright, just, pre-commit, pytest

**Node/TS:** npm, typescript, prisma, ts-node, nodemon, eslint, prettier, jest

**Dev tools:** git, gh, tmux, neovim, ripgrep, jq, delta, Docker CLI

**Claude Code:** latest, runs with `--dangerously-skip-permissions`

## Sibling Databases

Uncomment services in `docker-compose.yml` to spin up databases alongside the worker:

- **PostgreSQL 16 + PostGIS** (port 5432)
- **Qdrant** (port 6333)
- **ClickHouse** (ports 8123, 9000)

## Credentials

All secrets are injected at runtime via environment variables (never baked into the image).

See `.env.example` for the full list. At minimum you need:
- `ANTHROPIC_API_KEY`
- `GITHUB_TOKEN`

SSH keys are mounted read-only from `~/.ssh/`.

## How It Works

1. `ccw run` starts a Docker container from the pre-built image
2. The entrypoint clones the repo and creates a branch `claude/<task-slug>`
3. Claude Code runs with your prompt in `--dangerously-skip-permissions` mode
4. Claude commits work in phases, pushes the branch, creates a PR
5. Container stays alive so you can attach/SSH/inspect
6. You review the PR on GitHub, then `ccw kill` the container

## Publishing the Image

```bash
# Tag and push to GitHub Container Registry
docker tag ccw-worker ghcr.io/YOUR_USERNAME/ccw-worker:latest
docker push ghcr.io/YOUR_USERNAME/ccw-worker:latest

# Pull on another machine
docker pull ghcr.io/YOUR_USERNAME/ccw-worker:latest
```
