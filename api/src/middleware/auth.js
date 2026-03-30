'use strict';

const crypto = require('crypto');
const config = require('../config');

/**
 * API key authentication middleware.
 * Accepts key via X-API-Key header or Authorization: Bearer <key>.
 * Uses timing-safe comparison to prevent timing attacks.
 */
function auth(req, res, next) {
  // Extract key from either header style
  const apiKey =
    req.headers['x-api-key'] ||
    (req.headers.authorization && req.headers.authorization.startsWith('Bearer ')
      ? req.headers.authorization.slice(7)
      : null);

  if (!apiKey) {
    return res.status(401).json({
      error: 'unauthorized',
      message:
        'Missing API key. Provide via X-API-Key header or Authorization: Bearer <key>',
    });
  }

  // Timing-safe comparison
  const expected = Buffer.from(config.API_KEY);
  const provided = Buffer.from(apiKey);

  if (
    expected.length !== provided.length ||
    !crypto.timingSafeEqual(expected, provided)
  ) {
    return res.status(403).json({
      error: 'forbidden',
      message: 'Invalid API key',
    });
  }

  next();
}

module.exports = auth;
