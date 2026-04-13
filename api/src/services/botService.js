'use strict';

const fs = require('fs');
const path = require('path');
const config = require('../config');
const { getContainerStatus, getContainerDetails } = require('./dockerService');
const { withPortRegistryLock } = require('./lockService');
const { runScript } = require('../utils/scriptRunner');
const { logger } = require('../middleware/requestLogger');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Parse .port-registry file into an array of { name, offset } objects.
 */
function parsePortRegistry() {
  let content;
  try {
    content = fs.readFileSync(config.PORT_REGISTRY, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }

  return content
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .map((line) => {
      const [name, offsetStr] = line.split(/\s+/);
      return { name, offset: parseInt(offsetStr, 10) };
    })
    .filter((entry) => entry.name && !isNaN(entry.offset));
}

/**
 * Calculate external port from an offset.
 */
function externalPort(offset) {
  return config.BASE_PORT + (offset - 1);
}

/**
 * Container name for a given bot.
 */
function containerName(botName) {
  return `openclaw-bot-${botName}`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * List all registered bots with their container status.
 */
async function listBots() {
  const entries = parsePortRegistry();

  const bots = await Promise.all(
    entries.map(async ({ name, offset }) => {
      const container = containerName(name);
      const status = await getContainerStatus(container);
      return {
        name,
        port: externalPort(offset),
        status,
        container,
      };
    }),
  );

  return { bots, total: bots.length };
}

/**
 * Get detailed info for a single bot.
 */
async function getBot(name) {
  const entries = parsePortRegistry();
  const entry = entries.find((e) => e.name === name);

  if (!entry) {
    return null; // bot not found
  }

  const container = containerName(name);
  const details = await getContainerDetails(container);

  // Read non-sensitive config metadata
  let configMeta = null;
  try {
    const configPath = path.join(config.BOTS_DIR, name, 'config.json');
    const raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));

    // Extract model from agents.defaults.model.primary (format: "claudible/model-id")
    const modelRaw = raw?.agents?.defaults?.model?.primary || '';
    const model = modelRaw.includes('/') ? modelRaw.split('/').pop() : modelRaw;

    // Extract allowed chat IDs from telegram channel config
    const telegram = raw?.channels?.telegram || {};
    const allowedChatIds = telegram.allowFrom || [];

    configMeta = {
      model: model || 'unknown',
      allowedChatIds,
      telegramEnabled: !!(raw?.plugins?.entries?.find?.((p) =>
        typeof p === 'string' ? p === 'telegram' : p?.id === 'telegram',
      )),
    };
  } catch {
    // Config may not exist or be unreadable — that's ok
  }

  const result = {
    name,
    port: externalPort(entry.offset),
    container: {
      name: container,
      status: details?.State?.Status || 'not_found',
      health: details?.State?.Health?.Status || 'unknown',
      created: details?.Created || null,
      startedAt: details?.State?.StartedAt || null,
      restartCount: details?.RestartCount || 0,
    },
  };

  if (configMeta) {
    result.config = configMeta;
  }

  return result;
}

/**
 * Deploy a new bot by calling deploy-bot.sh.
 * Acquires a file lock on .port-registry for concurrency safety.
 */
async function deployBot({ name, telegramToken, chatIds, model }) {
  return withPortRegistryLock(async () => {
    // Check if bot already exists
    const entries = parsePortRegistry();
    if (entries.some((e) => e.name === name)) {
      const err = new Error(`Bot '${name}' already exists`);
      err.statusCode = 409;
      err.code = 'conflict';
      throw err;
    }

    // Also check if directory exists (partial deploy leftovers)
    const botDir = path.join(config.BOTS_DIR, name);
    if (fs.existsSync(botDir)) {
      const err = new Error(
        `Bot '${name}' directory already exists (possible partial deploy). Remove it first.`,
      );
      err.statusCode = 409;
      err.code = 'conflict';
      throw err;
    }

    // Build args: <name> <token> <chatIds> [model]
    const args = [name, telegramToken, chatIds.join(',')];
    if (model) args.push(model);

    logger.info({ message: `Deploying bot '${name}'`, model: model || 'claude-sonnet-4.6' });

    try {
      const result = await runScript(config.DEPLOY_SCRIPT, args, {
        timeout: config.DEPLOY_TIMEOUT,
      });

      logger.info({ message: `Bot '${name}' deployed successfully`, output: result.stdout });

      // Re-read registry to get the assigned port
      const updatedEntries = parsePortRegistry();
      const newEntry = updatedEntries.find((e) => e.name === name);
      const status = await getContainerStatus(containerName(name));

      return {
        name,
        port: newEntry ? externalPort(newEntry.offset) : null,
        status,
        container: containerName(name),
        model: model || 'claude-sonnet-4.6',
        message: 'Bot deployed successfully',
      };
    } catch (err) {
      logger.error({ message: `Deploy failed for '${name}'`, error: err.message, output: err.output });
      const deployErr = new Error(`Deploy failed: ${err.message}`);
      deployErr.statusCode = 500;
      deployErr.code = 'deploy_failed';
      deployErr.output = err.output || '';
      throw deployErr;
    }
  });
}

/**
 * Remove a bot by calling remove-bot.sh --force.
 * Acquires a file lock on .port-registry for concurrency safety.
 */
async function removeBot(name, keepData = false) {
  return withPortRegistryLock(async () => {
    // Check bot exists
    const entries = parsePortRegistry();
    const botDir = path.join(config.BOTS_DIR, name);

    if (!entries.some((e) => e.name === name) && !fs.existsSync(botDir)) {
      const err = new Error(`Bot '${name}' not found`);
      err.statusCode = 404;
      err.code = 'not_found';
      throw err;
    }

    // Build args: <name> --force [--keep-data]
    const args = [name, '--force'];
    if (keepData) args.push('--keep-data');

    logger.info({ message: `Removing bot '${name}'`, keepData });

    try {
      const result = await runScript(config.REMOVE_SCRIPT, args, {
        timeout: config.REMOVE_TIMEOUT,
      });

      logger.info({ message: `Bot '${name}' removed successfully`, output: result.stdout });

      return {
        message: `Bot '${name}' removed successfully`,
        keepData,
      };
    } catch (err) {
      logger.error({ message: `Remove failed for '${name}'`, error: err.message, output: err.output });
      const removeErr = new Error(`Remove failed: ${err.message}`);
      removeErr.statusCode = 500;
      removeErr.code = 'remove_failed';
      removeErr.output = err.output || '';
      throw removeErr;
    }
  });
}

module.exports = { listBots, getBot, deployBot, removeBot };
