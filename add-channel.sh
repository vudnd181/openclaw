#!/bin/bash
set -euo pipefail

# add-channel.sh — Add a new Telegram channel (account) to an existing bot
#
# Usage:
#   ./add-channel.sh <bot_name> <channel_name> <telegram_token> <chat_ids>
#
# Arguments:
#   bot_name        Existing bot to add the channel to (e.g., duc, alice)
#   channel_name    Unique label for this channel (e.g., work, group2, support)
#   telegram_token  New Telegram bot token from @BotFather
#   chat_ids        Comma-separated Telegram user/chat IDs to allow
#
# Examples:
#   ./add-channel.sh duc  work    123456:ABC 658635669
#   ./add-channel.sh duc  group2  987654:XYZ 658635669,123456789
#
# What it does:
#   1. Validates bot exists and channel name is unique
#   2. Backs up config.json before modifying
#   3. Injects a new account block into channels.telegram.accounts
#   4. Adds the new token to .env
#   5. Restarts ONLY the target bot (--no-deps — other bots untouched)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"

# ─── Argument Parsing ────────────────────────────────────────────────────────
BOT_NAME="${1:-}"
CHANNEL_NAME="${2:-}"
TELEGRAM_TOKEN="${3:-}"
CHAT_IDS="${4:-}"

if [ -z "$BOT_NAME" ] || [ -z "$CHANNEL_NAME" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_IDS" ]; then
    echo "Usage: ./add-channel.sh <bot_name> <channel_name> <telegram_token> <chat_ids>"
    echo ""
    echo "Arguments:"
    echo "  bot_name        Existing bot name (e.g., duc, alice)"
    echo "  channel_name    Unique label for the new channel (e.g., work, group2)"
    echo "  telegram_token  Telegram bot token from @BotFather"
    echo "  chat_ids        Comma-separated Telegram user/chat IDs to allow"
    echo ""
    echo "Examples:"
    echo "  ./add-channel.sh duc work   123456:ABC 658635669"
    echo "  ./add-channel.sh duc group2 987654:XYZ 658635669,123456789"
    exit 1
fi

# ─── Validate names ──────────────────────────────────────────────────────────
if [[ ! "$BOT_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "❌ Invalid bot_name '$BOT_NAME' — must be lowercase alphanumeric with optional hyphens"
    exit 1
fi

if [[ ! "$CHANNEL_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "❌ Invalid channel_name '$CHANNEL_NAME' — must be lowercase alphanumeric with optional hyphens"
    exit 1
fi

# ─── Check bot exists ────────────────────────────────────────────────────────
CONFIG="$BOTS_DIR/$BOT_NAME/config.json"

if [ ! -d "$BOTS_DIR/$BOT_NAME" ]; then
    echo "❌ Bot '$BOT_NAME' not found at bots/$BOT_NAME/"
    echo "   Available bots:"
    ls "$BOTS_DIR" 2>/dev/null | grep -v '^\.' | sed 's/^/     /' || echo "     (none)"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "❌ Config not found: bots/$BOT_NAME/config.json"
    exit 1
fi

# ─── Check channel name is unique within this bot ────────────────────────────
if grep -q "\"${CHANNEL_NAME}\":" "$CONFIG"; then
    echo "❌ Channel '$CHANNEL_NAME' already exists in bot '$BOT_NAME'"
    echo "   Existing accounts:"
    grep -oP '"[^"]+(?="\s*:\s*\{)' "$CONFIG" | grep -v '^\s*$' | ~sed 's/^/     /' || true
    exit 1
fi

# ─── Check container is running ──────────────────────────────────────────────
SERVICE_NAME="openclaw-bot-${BOT_NAME}"
if ! docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    echo "⚠️  Warning: container '$SERVICE_NAME' is not running."
    echo "   The config will be updated, but you'll need to start the bot manually."
    echo ""
fi

# ─── Backup config ───────────────────────────────────────────────────────────
BACKUP="${CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$BACKUP"
echo "📦 Backed up config → $(basename "$BACKUP")"

# ─── Build the JSON account block ────────────────────────────────────────────
# Convert "123,456,789" → ["123","456","789"]
ALLOW_FROM_JSON=$(echo "$CHAT_IDS" | sed 's/,/", "/g')

# Indent: 8 spaces to sit inside "accounts": { ... }
NEW_ACCOUNT_BLOCK=$(cat <<JSON
        "${CHANNEL_NAME}": {
          "botToken": "${TELEGRAM_TOKEN}",
          "dmPolicy": "allowlist",
          "allowFrom": ["${ALLOW_FROM_JSON}"],
          "groupPolicy": "allowlist",
          "streaming": "partial"
        }
JSON
)

# ─── Inject into config.json ─────────────────────────────────────────────────
# Strategy: find the closing brace of the "accounts" object and insert before it.
# The "accounts" block ends with a line that is exactly 6-spaces + "}" (the object
# closing brace), right before the outer telegram block closes.
# We use Python (available in the node:20-alpine image too, but here on the host)
# for safe JSON editing — avoids fragile sed/awk on nested JSON.

if command -v python3 &>/dev/null; then
    python3 - "$CONFIG" "$CHANNEL_NAME" "$TELEGRAM_TOKEN" "$CHAT_IDS" <<'PYEOF'
import sys, json

config_path  = sys.argv[1]
channel_name = sys.argv[2]
bot_token    = sys.argv[3]
chat_ids_raw = sys.argv[4]

# Parse the allowed chat IDs
allow_from = [cid.strip() for cid in chat_ids_raw.split(",") if cid.strip()]

with open(config_path, "r") as f:
    cfg = json.load(f)

accounts = cfg.setdefault("channels", {}).setdefault("telegram", {}).setdefault("accounts", {})

if channel_name in accounts:
    print(f"❌ Channel '{channel_name}' already exists (Python check).", file=sys.stderr)
    sys.exit(1)

accounts[channel_name] = {
    "botToken": bot_token,
    "dmPolicy": "allowlist",
    "allowFrom": allow_from,
    "groupPolicy": "allowlist",
    "streaming": "partial"
}

with open(config_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"  ✅ Injected account '{channel_name}' into channels.telegram.accounts")
PYEOF

elif command -v node &>/dev/null; then
    # Fallback: use Node.js (always available on this host)
    node - "$CONFIG" "$CHANNEL_NAME" "$TELEGRAM_TOKEN" "$CHAT_IDS" <<'JSEOF'
const fs   = require("fs");
const path = process.argv[2];
const name = process.argv[3];
const tok  = process.argv[4];
const ids  = process.argv[5].split(",").map(s => s.trim()).filter(Boolean);

const cfg = JSON.parse(fs.readFileSync(path, "utf8"));
const accounts = ((cfg.channels ||= {}).telegram ||= {}).accounts ||= {};

if (accounts[name]) {
    console.error(`❌ Channel '${name}' already exists (Node check).`);
    process.exit(1);
}

accounts[name] = {
    botToken:    tok,
    dmPolicy:    "allowlist",
    allowFrom:   ids,
    groupPolicy: "allowlist",
    streaming:   "partial"
};

fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
console.log(`  ✅ Injected account '${name}' into channels.telegram.accounts`);
JSEOF

else
    echo "❌ Neither python3 nor node found on this host."
    echo "   Restoring backup..."
    cp "$BACKUP" "$CONFIG"
    exit 1
fi

# ─── Add token to .env ───────────────────────────────────────────────────────
BOT_SUFFIX=$(echo "$BOT_NAME"     | tr '[:lower:]-' '[:upper:]_')
CH_SUFFIX=$(echo "$CHANNEL_NAME"  | tr '[:lower:]-' '[:upper:]_')
ENV_VAR="TOKEN_${BOT_SUFFIX}_${CH_SUFFIX}"

if grep -q "^${ENV_VAR}=" "$SCRIPT_DIR/.env" 2>/dev/null; then
    echo "  ℹ️  $ENV_VAR already in .env — skipping"
else
    cat >> "$SCRIPT_DIR/.env" <<EOF

# Bot: $BOT_NAME — channel: $CHANNEL_NAME
${ENV_VAR}=${TELEGRAM_TOKEN}
EOF
    echo "  ✅ Added ${ENV_VAR} to .env"
fi

# ─── Restart ONLY the target bot ─────────────────────────────────────────────
echo ""
echo "🔄 Restarting '$SERVICE_NAME' (other bots untouched)..."
if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" restart "$SERVICE_NAME"
    echo "✅ '$SERVICE_NAME' restarted"
else
    echo "ℹ️  Container not running — start it with:"
    echo "   docker compose up -d --no-deps $SERVICE_NAME"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "🎉 Channel '$CHANNEL_NAME' added to bot '$BOT_NAME'!"
echo ""
echo "   Bot:          $BOT_NAME"
echo "   New channel:  $CHANNEL_NAME"
echo "   Token var:    $ENV_VAR"
echo "   Allowed IDs:  $CHAT_IDS"
echo "   Config:       bots/$BOT_NAME/config.json"
echo "   Backup:       $(basename "$BACKUP")"
echo ""
echo "📋 View logs: docker compose logs -f $SERVICE_NAME"
