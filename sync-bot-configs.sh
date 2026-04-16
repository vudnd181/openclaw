#!/bin/bash
set -euo pipefail

# sync-bot-configs.sh — Sync shared settings from config.bot.template.json to all existing bots.
# Preserves per-bot secrets: token, chat IDs, API key, gateway token, model, allowedOrigins.
#
# Usage:
#   ./sync-bot-configs.sh               # dry-run (show what would change)
#   ./sync-bot-configs.sh --apply       # apply changes
#   ./sync-bot-configs.sh --apply --restart  # apply + restart affected bots
#   ./sync-bot-configs.sh --bot vu --apply   # apply to one bot only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"
TEMPLATE="$SCRIPT_DIR/config.bot.template.json"

# --- Flags ---
APPLY=false
RESTART=false
TARGET_BOT=""

for arg in "$@"; do
    case "$arg" in
        --apply)   APPLY=true ;;
        --restart) RESTART=true ;;
        --bot)     shift; TARGET_BOT="${1:-}" ;;
        --bot=*)   TARGET_BOT="${arg#--bot=}" ;;
    esac
done

# Restart implies apply
if [ "$RESTART" = true ]; then APPLY=true; fi

# --- Checks ---
if [ ! -f "$TEMPLATE" ]; then
    echo "❌ Template not found: $TEMPLATE"
    exit 1
fi

if [ ! -f "$PORT_REGISTRY" ] || [ ! -s "$PORT_REGISTRY" ]; then
    echo "⚠️  No bots registered."
    exit 0
fi

if [ "$APPLY" = false ]; then
    echo "ℹ️  DRY-RUN mode — no files will be changed. Pass --apply to write changes."
    echo ""
fi

PATCHED_BOTS=()

while IFS=' ' read -r bot_name port_offset; do
    [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue

    # Filter to specific bot if --bot was given
    if [ -n "$TARGET_BOT" ] && [ "$bot_name" != "$TARGET_BOT" ]; then
        continue
    fi

    CONFIG="$BOTS_DIR/$bot_name/config.json"
    if [ ! -f "$CONFIG" ]; then
        echo "⚠️  Skipping $bot_name — no config.json"
        continue
    fi

    # Run Python to compute diff and optionally apply
    RESULT=$(python3 - "$CONFIG" "$TEMPLATE" "$APPLY" <<'PYEOF'
import json, sys

config_path = sys.argv[1]
template_path = sys.argv[2]
do_apply = sys.argv[3] == "True"

with open(config_path) as f:
    cfg = json.load(f)
with open(template_path) as f:
    tpl = json.load(f)

changes = []

def sync_value(cfg, tpl, path):
    """Sync a scalar value from tpl to cfg, record change if different."""
    keys = path.split(".")
    # Navigate to parent in both dicts
    c, t = cfg, tpl
    for k in keys[:-1]:
        if k not in t:
            return  # not in template, skip
        c = c.setdefault(k, {})
        t = t[k]
    leaf = keys[-1]
    if leaf not in t:
        return  # not in template, skip
    old_val = c.get(leaf)
    new_val = t[leaf]
    if old_val != new_val:
        changes.append(f"  {path}: {json.dumps(old_val)} → {json.dumps(new_val)}")
        if do_apply:
            c[leaf] = new_val

def sync_list(cfg, tpl, path):
    """Sync a list value from tpl to cfg."""
    sync_value(cfg, tpl, path)  # same logic for lists

# ── Fields synced from template (non-sensitive) ──────────────────────────────
# Agent concurrency
sync_value(cfg, tpl, "agents.defaults.maxConcurrent")
sync_value(cfg, tpl, "agents.defaults.subagents.maxConcurrent")

# Tool settings
sync_value(cfg, tpl, "tools.elevated.enabled")
sync_value(cfg, tpl, "tools.exec.ask")

# Command settings
sync_value(cfg, tpl, "commands.native")
sync_value(cfg, tpl, "commands.nativeSkills")

# Message settings
sync_value(cfg, tpl, "messages.ackReactionScope")

# Gateway tailscale (not secrets) — NOTE: gateway.mode is intentionally NOT synced
# because "server" mode disables device pairing. Keep per-bot as-is.
sync_value(cfg, tpl, "gateway.tailscale.mode")
sync_value(cfg, tpl, "gateway.tailscale.resetOnExit")
sync_list (cfg, tpl, "gateway.trustedProxies")

# Model list (providers catalog, not the API key)
try:
    tpl_models = tpl["models"]["providers"]["claudible"]["models"]
    cfg_models = cfg.get("models", {}).get("providers", {}).get("claudible", {}).get("models")
    if cfg_models != tpl_models:
        changes.append(f"  models.providers.claudible.models: (model catalog updated)")
        if do_apply:
            cfg["models"]["providers"]["claudible"]["models"] = tpl_models
except (KeyError, TypeError):
    pass

# ── Fields intentionally NOT synced (per-bot secrets / unique values) ────────
# - models.providers.claudible.apiKey
# - models.providers.claudible.baseUrl
# - agents.defaults.model.primary        (per-bot model choice)
# - channels.telegram.accounts.*.botToken
# - channels.telegram.allowFrom / accounts.*.allowFrom
# - gateway.auth.token
# - gateway.controlUi.allowedOrigins     (has bot-specific HTTPS origin)
# - env.TELEGRAM_BOT_TOKEN

if do_apply and changes:
    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)

if changes:
    print("CHANGED\n" + "\n".join(changes))
else:
    print("NO_CHANGE")
PYEOF
)

    if echo "$RESULT" | grep -q "^NO_CHANGE"; then
        echo "  ✅ $bot_name — already up to date"
    else
        DIFF=$(echo "$RESULT" | tail -n +2)
        if [ "$APPLY" = false ]; then
            echo "  📋 $bot_name — would update:"
            echo "$DIFF"
        else
            echo "  ✅ $bot_name — updated:"
            echo "$DIFF"
            PATCHED_BOTS+=("$bot_name")
        fi
    fi

done < "$PORT_REGISTRY"

# --- Restart patched bots if requested ---
if [ "$RESTART" = true ] && [ "${#PATCHED_BOTS[@]}" -gt 0 ]; then
    echo ""
    echo "🔄 Restarting updated bots..."
    for bot in "${PATCHED_BOTS[@]}"; do
        echo "   Restarting openclaw-bot-${bot}..."
        docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --no-deps --force-recreate "openclaw-bot-${bot}"
        echo "   ✅ openclaw-bot-${bot} restarted"
    done
fi

# --- Summary ---
echo ""
if [ "$APPLY" = false ]; then
    echo "Run with --apply to apply these changes."
    echo "Run with --apply --restart to apply and restart affected bots."
else
    if [ "${#PATCHED_BOTS[@]}" -gt 0 ]; then
        echo "✅ Patched ${#PATCHED_BOTS[@]} bot(s): ${PATCHED_BOTS[*]}"
        if [ "$RESTART" = false ]; then
            echo ""
            echo "Restart bots to apply:"
            for bot in "${PATCHED_BOTS[@]}"; do
                echo "  docker compose up -d --no-deps --force-recreate openclaw-bot-${bot}"
            done
        fi
    else
        echo "✅ All bots already up to date — nothing changed."
    fi
fi
