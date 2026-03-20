#!/bin/sh
# Copy config into the writable volume as openclaw.json (always overwrite to stay in sync)
# The source config is bind-mounted at /config/config.json (read-only)
if [ -f /config/config.json ]; then
  cp /config/config.json /home/node/.openclaw/openclaw.json
fi

# Fix ownership of everything in the data dir
chown -R node:node /home/node/.openclaw 2>/dev/null || true

# Ensure workspace directory exists
mkdir -p /home/node/.openclaw/workspace 2>/dev/null || true
chown node:node /home/node/.openclaw/workspace 2>/dev/null || true

# Apply elevated tools config
sudo -u node /usr/local/bin/openclaw config set tools.elevated.enabled true 2>/dev/null || true
sudo -u node /usr/local/bin/openclaw config set tools.elevated.allowFrom.telegram true 2>/dev/null || true

# Configure web section
sudo -u node /usr/local/bin/openclaw configure --section web 2>/dev/null || true

# Drop to node user and start OpenClaw gateway in foreground
# --bind lan binds to 0.0.0.0 so Docker port mapping works
exec sudo -u node /usr/local/bin/openclaw gateway run --allow-unconfigured --bind lan --port 18789
