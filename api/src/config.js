'use strict';

const path = require('path');

const WORKSPACE = process.env.WORKSPACE || '/workspace';

module.exports = {
  // Server
  PORT: parseInt(process.env.PORT || '18800', 10),
  API_KEY: process.env.API_KEY || '',
  LOG_LEVEL: process.env.LOG_LEVEL || 'info',
  NODE_ENV: process.env.NODE_ENV || 'development',

  // Paths (relative to /workspace — the mounted project root)
  WORKSPACE,
  BOTS_DIR: path.join(WORKSPACE, 'bots'),
  PORT_REGISTRY: path.join(WORKSPACE, 'bots', '.port-registry'),
  DEPLOY_SCRIPT: path.join(WORKSPACE, 'deploy-bot.sh'),
  REMOVE_SCRIPT: path.join(WORKSPACE, 'remove-bot.sh'),

  // Constants (must match shell scripts)
  BASE_PORT: 18789,
  VALID_MODELS: ['claude-haiku-4.5', 'claude-sonnet-4.6', 'claude-opus-4.6'],
  BOT_NAME_REGEX: /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
  BOT_NAME_MAX_LENGTH: 30,

  // Timeouts (ms)
  DEPLOY_TIMEOUT: 120_000,   // 2 min — build + health check can be slow
  REMOVE_TIMEOUT: 60_000,    // 1 min
  DOCKER_INSPECT_TIMEOUT: 10_000,

  // Rate limiting
  READ_RATE_LIMIT: 120,   // requests per minute
  WRITE_RATE_LIMIT: 30,   // requests per minute
};
