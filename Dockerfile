FROM node:22-alpine

WORKDIR /app

# Install dependencies and OpenClaw
# git is required by openclaw's npm dependencies; su-exec for dropping privileges
RUN apk add --no-cache curl git su-exec && npm install -g openclaw@latest

# Create workspace
RUN mkdir -p /home/node/.openclaw/workspace && chown -R node:node /home/node/.openclaw

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Expose gateway port
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:18789/health || exit 1

# Entrypoint fixes volume permissions then drops to node user
ENTRYPOINT ["entrypoint.sh"]
