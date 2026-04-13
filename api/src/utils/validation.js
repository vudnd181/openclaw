'use strict';

const config = require('../config');

const TELEGRAM_TOKEN_REGEX = /^\d+:.+$/;

/**
 * Validate input for deploying a new bot.
 * Returns an array of error objects; empty array = valid.
 */
function validateDeployInput(body) {
  const errors = [];

  // name (required)
  if (!body.name || typeof body.name !== 'string') {
    errors.push({ field: 'name', message: 'name is required' });
  } else if (!config.BOT_NAME_REGEX.test(body.name)) {
    errors.push({
      field: 'name',
      message:
        'Must be lowercase alphanumeric with optional hyphens, cannot start/end with hyphen',
    });
  } else if (body.name.length > config.BOT_NAME_MAX_LENGTH) {
    errors.push({
      field: 'name',
      message: `Must be ${config.BOT_NAME_MAX_LENGTH} characters or fewer`,
    });
  }

  // telegramToken (required)
  if (!body.telegramToken || typeof body.telegramToken !== 'string') {
    errors.push({ field: 'telegramToken', message: 'telegramToken is required' });
  } else if (!TELEGRAM_TOKEN_REGEX.test(body.telegramToken.trim())) {
    errors.push({
      field: 'telegramToken',
      message: 'Invalid Telegram token format (expected: 123456:ABC...)',
    });
  }

  // chatIds (optional — can be set up later)
  if (body.chatIds !== undefined && body.chatIds !== null) {
    if (!Array.isArray(body.chatIds)) {
      errors.push({
        field: 'chatIds',
        message: 'chatIds must be an array of numeric strings',
      });
    } else {
      for (const id of body.chatIds) {
        if (typeof id !== 'string' || !/^-?\d+$/.test(id)) {
          errors.push({
            field: 'chatIds',
            message: `Invalid chat ID: "${id}" (must be a numeric string, can be negative for groups)`,
          });
          break; // report first bad ID only
        }
      }
    }
  }

  // model (optional)
  if (body.model !== undefined && body.model !== null) {
    if (typeof body.model !== 'string' || !config.VALID_MODELS.includes(body.model)) {
      errors.push({
        field: 'model',
        message: `Invalid model. Must be one of: ${config.VALID_MODELS.join(', ')}`,
      });
    }
  }

  return errors;
}

/**
 * Validate a bot name path parameter.
 * Returns an error string or null if valid.
 */
function validateBotName(name) {
  if (!name || typeof name !== 'string') {
    return 'Bot name is required';
  }
  if (!config.BOT_NAME_REGEX.test(name)) {
    return 'Invalid bot name format';
  }
  if (name.length > config.BOT_NAME_MAX_LENGTH) {
    return `Bot name must be ${config.BOT_NAME_MAX_LENGTH} characters or fewer`;
  }
  return null;
}

module.exports = {
  validateDeployInput,
  validateBotName,
};
