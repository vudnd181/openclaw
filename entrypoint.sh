#!/bin/sh
# Copy config into the writable volume as openclaw.json (always overwrite to stay in sync)
# The source config is bind-mounted at /config/config.json (read-only)
if [ -f /config/config.json ]; then
  cp /config/config.json /home/node/.openclaw/openclaw.json
fi

# Inject bot's HTTPS origin into allowedOrigins so the dashboard works from the bot's domain
if [ -n "${BOT_ORIGIN:-}" ]; then
  sed -i "s|\"allowedOrigins\": \[\"http://localhost:18789\"\]|\"allowedOrigins\": [\"http://localhost:18789\", \"${BOT_ORIGIN}\"]|" \
    /home/node/.openclaw/openclaw.json
fi

# Fix ownership of everything in the data dir
chown -R node:node /home/node/.openclaw 2>/dev/null || true

# Ensure workspace directory exists
mkdir -p /home/node/.openclaw/workspace 2>/dev/null || true
chown node:node /home/node/.openclaw/workspace 2>/dev/null || true

# Apply elevated tools config
sudo -u node /usr/local/bin/openclaw config set tools.elevated.enabled true 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.elevated.allowFrom.telegram true 2>/dev/null || true

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
