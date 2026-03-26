FROM node:22

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl git sudo python3 python3-pip \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libpango-1.0-0 libcairo2 libatspi2.0-0 \
    fonts-liberation libappindicator3-1 libx11-xcb1 \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* && \
    npm install -g openclaw@latest && \
    npm install -g --os=linux --cpu=x64 sharp && \
    openclaw plugins install acpx && \
    echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# GUI stack: Xvfb + Chromium + VNC + noVNC + supervisor
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    chromium \
    x11vnc \
    novnc \
    python3-websockify \
    libxtst6 \
    libxss1 \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/node/.openclaw/workspace && chown -R node:node /home/node/.openclaw

# Supervisor config (manages Xvfb, x11vnc, websockify, openclaw)
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# VNC password setup script
COPY setup-vnc-passwd.sh /usr/local/bin/setup-vnc-passwd.sh
RUN chmod +x /usr/local/bin/setup-vnc-passwd.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV DISPLAY=:99
ENV VNC_PASSWORD=changeme
ENV SCREEN_RESOLUTION=1280x1024x24

EXPOSE 18789
EXPOSE 18927
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:18789/health || exit 1

ENTRYPOINT ["entrypoint.sh"]