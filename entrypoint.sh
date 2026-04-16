#!/bin/sh
# ============================================================
# entrypoint.sh — Persistent data-aware startup
# ============================================================

DATA_DIR="/home/node/.openclaw"
SKEL_DIR="/home/node/.openclaw-skel"
MARKER="$DATA_DIR/.initialized"

# ---------- 1. Seed volume on first run ----------
if [ ! -f "$MARKER" ]; then
  echo "[entrypoint] First run — seeding data volume..."
  if [ -d "$SKEL_DIR" ]; then
    cp -a "$SKEL_DIR/." "$DATA_DIR/"
  fi
  mkdir -p "$DATA_DIR/workspace"
  touch "$MARKER"
fi

# ---------- 2. Sync config (always overwrite — source of truth) ----------
if [ -f /config/config.json ]; then
  cp /config/config.json "$DATA_DIR/openclaw.json"
fi

# Patch config via Python — inject BOT_ORIGIN and remove stale plugins
BOT_ORIGIN="${BOT_ORIGIN:-}" python3 - <<'PYEOF'
import json, os

config_path = "/home/node/.openclaw/openclaw.json"
known_plugins = {"telegram", "acpx"}
bot_origin = os.environ.get("BOT_ORIGIN", "")

try:
    with open(config_path) as f:
        cfg = json.load(f)

    if bot_origin:
        origins = (cfg
            .setdefault("gateway", {})
            .setdefault("controlUi", {})
            .setdefault("allowedOrigins", ["http://localhost:18789"]))
        if bot_origin not in origins:
            origins.append(bot_origin)
            print(f"Added to allowedOrigins: {bot_origin}", flush=True)

    entries = cfg.get("plugins", {}).get("entries", {})
    stale = [k for k in entries if k not in known_plugins]
    for k in stale:
        del entries[k]
        print(f"Removed stale plugin entry: {k}", flush=True)

    with open(config_path, "w") as f:
        json.dump(cfg, f, indent=2)
except Exception as e:
    print(f"Config patch skipped: {e}", flush=True)
PYEOF

# ---------- 3. Ensure critical directories exist ----------
mkdir -p "$DATA_DIR/workspace" "$DATA_DIR/cache" "$DATA_DIR/skills" 2>/dev/null || true

chown node:node "$DATA_DIR" 2>/dev/null || true
chown node:node "$DATA_DIR/openclaw.json" 2>/dev/null || true
chown -R node:node "$DATA_DIR/workspace" "$DATA_DIR/cache" "$DATA_DIR/skills" 2>/dev/null || true

# ---------- 4. Ensure plugins are installed in the volume ----------
if ! sudo -u node /usr/local/bin/openclaw plugins list 2>/dev/null | grep -q "acpx"; then
  echo "[entrypoint] Installing acpx plugin into persistent volume..."
  sudo -u node /usr/local/bin/openclaw plugins install acpx 2>/dev/null || true
  ACPX_DIR=$(find /usr/local/lib/node_modules/openclaw -path "*/extensions/acpx" -type d 2>/dev/null | head -1)
  if [ -n "$ACPX_DIR" ]; then
    cd "$ACPX_DIR" && npm install --omit=dev --no-save --package-lock=false acpx@0.3.1 2>/dev/null || true
  fi
fi

# ---------- 5. Apply openclaw config settings ----------
sudo -u node /usr/local/bin/openclaw config set tools.elevated.enabled true 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.elevated.allowFrom.telegram true 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.exec.ask off 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set plugins.entries.acpx.enabled true 2>/dev/null || true

# ---------- 6. Start gateway ----------
exec sudo -u node /usr/local/bin/openclaw gateway run --allow-unconfigured --bind lan --port 18789
