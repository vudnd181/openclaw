FROM node:22

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git sudo python3 \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g openclaw@latest \
    && npm install -g --os=linux --cpu=x64 sharp \
    && openclaw plugins install acpx \
    && cd /usr/local/lib/node_modules/openclaw/dist/extensions/acpx \
    && npm install --omit=dev --no-save --package-lock=false acpx@0.3.1 \
    && echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && chown -R node:node /usr/local/lib/node_modules /usr/local/bin

RUN mkdir -p /home/node/.openclaw-skel/workspace && chown -R node:node /home/node/.openclaw-skel

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 18789

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

ENTRYPOINT ["entrypoint.sh"]
