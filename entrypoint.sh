#!/bin/sh
# Fix ownership of the data directory
chown -R node:node /home/node/.openclaw 2>/dev/null || true

# Copy config.json into the writable area as openclaw.json if it doesn't exist
# The config is bind-mounted at /config/config.json (read-only)
# OpenClaw reads/writes openclaw.json in its data dir
if [ ! -f /home/node/.openclaw/openclaw.json ] && [ -f /config/config.json ]; then
  cp /config/config.json /home/node/.openclaw/openclaw.json
  chown node:node /home/node/.openclaw/openclaw.json
fi

# Ensure workspace directory exists
mkdir -p /home/node/.openclaw/workspace 2>/dev/null || true

# Drop to node user and start OpenClaw gateway in foreground
# Use loopback bind (default) — Docker port mapping still works for localhost access
exec su-exec node /usr/local/bin/openclaw gateway run --allow-unconfigured --port 18789
