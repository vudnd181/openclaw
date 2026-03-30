'use strict';

const logger = require('./requestLogger').logger;

/**
 * Global error handler middleware.
 * Converts errors to structured JSON responses.
 */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  const statusCode = err.statusCode || 500;
  const code = err.code || 'internal_error';

  logger.error({
    message: err.message,
    code,
    statusCode,
    method: req.method,
    path: req.path,
    ...(err.output && { output: err.output }),
    ...(statusCode === 500 && { stack: err.stack }),
  });

  const body = {
    error: code,
    message: statusCode === 500 && !err.code
      ? 'An unexpected error occurred'
      : err.message,
  };

  if (err.details) body.details = err.details;
  if (err.output) body.output = err.output;

  res.status(statusCode).json(body);
}

/**
 * Create an operational error with status code and error code.
 */
function createError(statusCode, code, message, extra = {}) {
  const err = new Error(message);
  err.statusCode = statusCode;
  err.code = code;
  Object.assign(err, extra);
  return err;
}

module.exports = { errorHandler, createError };
