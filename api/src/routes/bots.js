'use strict';

const router = require('express').Router();
const botService = require('../services/botService');
const { validateDeployInput, validateBotName } = require('../utils/validation');
const { createError } = require('../middleware/errorHandler');

// ---------------------------------------------------------------------------
// GET /api/v1/bots — List all bots
// ---------------------------------------------------------------------------
router.get('/', async (_req, res, next) => {
  try {
    const result = await botService.listBots();
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// GET /api/v1/bots/:name — Get single bot details
// ---------------------------------------------------------------------------
router.get('/:name', async (req, res, next) => {
  try {
    const nameErr = validateBotName(req.params.name);
    if (nameErr) {
      throw createError(400, 'validation_error', nameErr);
    }

    const bot = await botService.getBot(req.params.name);
    if (!bot) {
      throw createError(404, 'not_found', `Bot '${req.params.name}' not found`);
    }

    res.json(bot);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// POST /api/v1/bots — Deploy a new bot
// ---------------------------------------------------------------------------
router.post('/', async (req, res, next) => {
  try {
    const errors = validateDeployInput(req.body);
    if (errors.length > 0) {
      throw createError(400, 'validation_error', 'Invalid input', { details: errors });
    }

    const result = await botService.deployBot({
      name: req.body.name,
      telegramToken: req.body.telegramToken.trim(),
      chatIds: req.body.chatIds,
      model: req.body.model || undefined,
    });

    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------------
// DELETE /api/v1/bots/:name — Remove a bot
// ---------------------------------------------------------------------------
router.delete('/:name', async (req, res, next) => {
  try {
    const nameErr = validateBotName(req.params.name);
    if (nameErr) {
      throw createError(400, 'validation_error', nameErr);
    }

    const keepData = req.query.keepData === 'true';
    const result = await botService.removeBot(req.params.name, keepData);

    res.json(result);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
