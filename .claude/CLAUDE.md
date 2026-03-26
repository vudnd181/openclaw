# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based deployment setup for running **OpenClaw** Telegram bots. OpenClaw is an npm-installable CLI tool that provides a gateway connecting to any OpenAI-compatible API endpoint (in this case, **Claudible**). The system is fully scalable — add or remove bots with a single command, without affecting running instances.

All bots share a **single Claudible API key** (defined once in `.env`). Each bot has its own Telegram token and allowed chat IDs.

## Architecture

```
openclaw_docker/
├── Dockerfile                  # Shared base image (node:20-alpine + openclaw)
├── config.bot.template.json    # Config template with placeholder values
├── docker-compose.yml          # AUTO-GENERATED — never edit manually
├── generate-compose.sh         # Generates docker-compose.yml from bots/
├── deploy-bot.sh               # Single-command bot deployment (3 args)
├── remove-bot.sh               # Clean bot removal
├── list-bots.sh                # Show all bots and their status
├── .env                        # Shared API key + per-bot Telegram tokens (gitignored)
├── .gitignore                  # Protects secrets from version control
├── bots/                       # Source of truth for all bots
│   ├── .port-registry          # Maps bot names → port offsets
│   └── <bot-name>/
│       └── config.json         # Full OpenClaw config with credentials injected
└── .claude/
    ├── CLAUDE.md               # This file
    └── claudible-setup.md      # Official Claudible + OpenClaw setup guide
```

### Key Concepts

- **Shared API key** — `CLAUDIBLE_API_KEY` is set once in `.env` and injected into every bot's `config.json` by `deploy-bot.sh`.
- **`bots/` directory** is the source of truth. Each bot = one folder with its own `config.json`.
- **`docker-compose.yml` is generated**, never edited manually. Run `./generate-compose.sh` to rebuild it from `bots/`.
- **`config.bot.template.json`** is the shared template with placeholder values. `deploy-bot.sh` uses `sed` to inject credentials.
- **Port scheme**: Bot with offset N → external port `18789 + (N - 1)`. Internal port is always `18789`.
- **Bot names** are human-readable strings (`duc`, `alice`, `support-bot`), not numbers.

## Configuration

OpenClaw uses a **JSON config file** (`config.json`), not environment variables, for provider/model setup:

| Config Path | Purpose |
|---|---|
| `models.providers.claudible.baseUrl` | `https://claudible.io/v1` |
| `models.providers.claudible.apiKey` | Claudible API key (shared, from `.env`) |
| `models.providers.claudible.api` | Must be `"openai-completions"` |
| `agents.defaults.model.primary` | Default model (format: `claudible/model-id`) |
| `channels.telegram.dmPolicy` | `"allowlist"` — only allowed chat IDs can DM |
| `channels.telegram.allowFrom` | List of specific Telegram user/chat IDs |
| `gateway.port` | `18789` (internal) |
| `gateway.bind` | `0.0.0.0` (required in Docker) |

See `config.bot.template.json` for the full structure and `.claude/claudible-setup.md` for the official guide.

## .env Format

```env
# Shared Claudible API key (used by all bots)
CLAUDIBLE_API_KEY=<your-claudible-api-key>

# Bot: duc
TOKEN_DUC=<telegram_bot_token>

# Bot: alice
TOKEN_ALICE=<telegram_bot_token>
```

The API key is defined **once** and read by `deploy-bot.sh` when creating new bots. Per-bot Telegram tokens are referenced by `docker-compose.yml` via env var substitution.

## Common Commands

### Deploy a new bot (single command — 3-4 args)
```bash
./deploy-bot.sh <name> <telegram_token> <chat_ids> [model]
# Example (single user, default model claude-haiku-4.5):
./deploy-bot.sh alice 987654:XYZ 658635669
# Example (multiple users, comma-separated):
./deploy-bot.sh alice 987654:XYZ 658635669,123456789
# Example (choose model):
./deploy-bot.sh alice 987654:XYZ 658635669 claude-sonnet-4.6
```
Available models: `claude-haiku-4.5` (default), `claude-sonnet-4.6`, `claude-opus-4.6`.

The API key is automatically read from `CLAUDIBLE_API_KEY` in `.env`. Chat IDs are comma-separated Telegram user IDs that are allowed to interact with the bot. This creates `bots/alice/config.json`, assigns a port, updates `.env`, regenerates `docker-compose.yml`, builds, and starts **only** the new bot.

### Remove a bot
```bash
./remove-bot.sh <name>
./remove-bot.sh <name> --keep-data   # keep Docker volume
```

### List all bots
```bash
./list-bots.sh
```

### Regenerate docker-compose.yml
```bash
./generate-compose.sh
```

### Build and run all bots
```bash
docker compose up -d --build
```

### View logs for a specific bot
```bash
docker compose logs -f openclaw-bot-<name>
```

### Rebuild a single bot
```bash
docker compose build openclaw-bot-<name>
docker compose up -d --no-deps openclaw-bot-<name>
```

### Stop all bots
```bash
docker compose down
```

## Safety: "Won't Touch Running Bots"

Three layers of protection when adding a new bot:

1. **Deterministic generation** — `generate-compose.sh` produces identical service blocks for unchanged bots.
2. **`--no-deps` flag** — `deploy-bot.sh` uses `docker compose up -d --no-deps <new-bot>` to only act on the new service.
3. **Docker's own diff check** — Compose only recreates containers whose definitions actually changed.

## Important Notes

- All bots share a **single Claudible API key** defined in `.env`. No need to pass it per bot.
- The API endpoint uses **Claudible** (`https://claudible.io/v1`), not the direct Anthropic API.
- OpenClaw uses the **OpenAI-compatible** API format (`openai-completions`), not native Anthropic format.
- The Dockerfile installs `curl` for the health check (`/health` on port 18789).
- The gateway binds to `0.0.0.0` inside Docker (not `loopback`) so port mapping works.
- `docker-compose.yml` is gitignored because it's generated. Don't edit it manually.
- `bots/*/config.json` is gitignored because it contains the API key.
- Uses `docker compose` (v2, no hyphen) — the modern standard.


## Check
- Get Gateway token:
  ```bash
  docker exec -u node openclaw-bot-vu cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -A2 '"token"' | head -3
  ```
- Approve device (browser dashboard):
  ```bash
  docker exec -u node openclaw-bot-duc /usr/local/bin/openclaw devices list
  docker exec -u node openclaw-bot-vu2 /usr/local/bin/openclaw devices approve <REQUEST_ID>
  ```
- Telegram DM policy is `"allowlist"` — only specified chat IDs can message the bot.