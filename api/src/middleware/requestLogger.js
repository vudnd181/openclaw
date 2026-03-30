'use strict';

const winston = require('winston');
const config = require('../config');

const logger = winston.createLogger({
  level: config.LOG_LEVEL,
  format: winston.format.combine(
    winston.format.timestamp(),
    config.NODE_ENV === 'production'
      ? winston.format.json()
      : winston.format.combine(winston.format.colorize(), winston.format.simple()),
  ),
  transports: [new winston.transports.Console()],
});

/**
 * HTTP request logging middleware.
 */
function requestLogger(req, res, next) {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    const level = res.statusCode >= 400 ? 'warn' : 'info';

    logger[level]({
      message: `${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms`,
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      duration,
    });
  });

  next();
}

module.exports = requestLogger;
module.exports.logger = logger;
