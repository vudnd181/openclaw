FROM node:22-alpine

WORKDIR /api

# Docker CLI (needed for docker inspect in list/status endpoints)
# bash (needed by shell scripts called via execFile)
RUN apk add --no-cache docker-cli docker-cli-compose bash

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

COPY src/ ./src/

USER node

EXPOSE 18800

CMD ["node", "src/index.js"]
