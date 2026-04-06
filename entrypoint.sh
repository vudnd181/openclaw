#!/bin/sh
# ============================================================
# entrypoint.sh — Persistent data-aware startup
#
# The Docker volume at /home/node/.openclaw persists across
# container rebuilds. This script is careful to:
#   1. Seed the volume only on FIRST run (empty volume)
#   2. Always sync openclaw.json from the bind-mounted config
#   3. Ensure plugins are installed INTO the volume
#   4. Avoid blowing away conversations, cache, skills, etc.
# ============================================================

DATA_DIR="/home/node/.openclaw"
SKEL_DIR="/home/node/.openclaw-skel"
MARKER="$DATA_DIR/.initialized"

# ---------- 1. Seed volume on first run ----------
# If the volume is brand new (empty), copy skeleton into it
if [ ! -f "$MARKER" ]; then
  echo "[entrypoint] First run — seeding data volume..."
  if [ -d "$SKEL_DIR" ]; then
    cp -a "$SKEL_DIR/." "$DATA_DIR/"
  fi
  mkdir -p "$DATA_DIR/workspace"
  touch "$MARKER"
fi

# ---------- 2. Sync config (always overwrite — source of truth) ----------
# The source config is bind-mounted at /config/config.json (read-only)
if [ -f /config/config.json ]; then
  cp /config/config.json "$DATA_DIR/openclaw.json"
fi

# Patch config via Python — robust JSON manipulation (no fragile sed)
# 1. Inject BOT_ORIGIN into allowedOrigins
# 2. Remove stale plugin entries
BOT_ORIGIN="${BOT_ORIGIN:-}" python3 - <<'PYEOF'
import json, os

config_path = "/home/node/.openclaw/openclaw.json"
known_plugins = {"telegram", "acpx"}
bot_origin = os.environ.get("BOT_ORIGIN", "")

try:
    with open(config_path) as f:
        cfg = json.load(f)

    # Fix allowedOrigins
    if bot_origin:
        origins = (cfg
            .setdefault("gateway", {})
            .setdefault("controlUi", {})
            .setdefault("allowedOrigins", ["http://localhost:18789"]))
        if bot_origin not in origins:
            origins.append(bot_origin)
            print(f"Added to allowedOrigins: {bot_origin}", flush=True)

    # Remove stale plugin entries
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
mkdir -p "$DATA_DIR/workspace" 2>/dev/null || true
mkdir -p "$DATA_DIR/cache" 2>/dev/null || true
mkdir -p "$DATA_DIR/skills" 2>/dev/null || true

# Fix ownership — only fix top-level + key dirs (avoid slow recursive chown)
chown node:node "$DATA_DIR" 2>/dev/null || true
chown node:node "$DATA_DIR/openclaw.json" 2>/dev/null || true
chown -R node:node "$DATA_DIR/workspace" 2>/dev/null || true
chown -R node:node "$DATA_DIR/cache" 2>/dev/null || true
chown -R node:node "$DATA_DIR/skills" 2>/dev/null || true

# ---------- 4. Ensure plugins are installed in the volume ----------
# Plugins must live in the persistent volume, not just the image layer.
# Check and install if missing.
if ! sudo -u node /usr/local/bin/openclaw plugins list 2>/dev/null | grep -q "acpx"; then
  echo "[entrypoint] Installing acpx plugin into persistent volume..."
  sudo -u node /usr/local/bin/openclaw plugins install acpx 2>/dev/null || true
  # Install acpx npm dep alongside the plugin
  ACPX_DIR=$(find /usr/local/lib/node_modules/openclaw -path "*/extensions/acpx" -type d 2>/dev/null | head -1)
  if [ -n "$ACPX_DIR" ]; then
    cd "$ACPX_DIR" && npm install --omit=dev --no-save --package-lock=false acpx@0.3.1 2>/dev/null || true
  fi
fi

# ---------- 5. Apply openclaw config settings ----------
sudo -u node /usr/local/bin/openclaw config set tools.elevated.enabled true 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.elevated.allowFrom.telegram true 2>/dev/null || true

# Configure browser/CDP tool to use Docker-compatible Chromium wrapper
sudo -u node /usr/local/bin/openclaw config set tools.browser.chromiumPath /usr/local/bin/chromium-docker 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.browser.headless false 2>/dev/null || true

# Enable acpx plugin
sudo -u node /usr/local/bin/openclaw config set plugins.entries.acpx.enabled true 2>/dev/null || true

# Configure web section
sudo -u node /usr/local/bin/openclaw configure --section web 2>/dev/null || true

# ---------- GUI SETUP ----------

# Create log directory for supervisor
mkdir -p /var/log/supervisor

# Set Chromium env vars so openclaw (or any child process) can launch it
export DISPLAY="${DISPLAY:-:99}"
export CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage --disable-software-rasterizer"

# Launch everything via supervisor (Xvfb, x11vnc, websockify, openclaw)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
