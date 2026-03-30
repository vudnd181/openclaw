'use strict';

const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const config = require('./config');
const auth = require('./middleware/auth');
const { errorHandler } = require('./middleware/errorHandler');
const requestLogger = require('./middleware/requestLogger');
const { logger } = require('./middleware/requestLogger');
const botsRouter = require('./routes/bots');
const healthRouter = require('./routes/health');

// ---------------------------------------------------------------------------
// Startup validation
// ---------------------------------------------------------------------------
if (!config.API_KEY) {
  console.error('FATAL: API_KEY environment variable is required. Set it in .env as OPENCLAW_API_KEY.');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Express app
// ---------------------------------------------------------------------------
const app = express();

// Security headers
app.use(helmet());

// Parse JSON bodies (limit size to prevent abuse)
app.use(express.json({ limit: '10kb' }));

// Request logging
app.use(requestLogger);

// Rate limiting
const readLimiter = rateLimit({
  windowMs: 60_000,
  max: config.READ_RATE_LIMIT,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'rate_limited', message: 'Too many requests. Please try again later.' },
});

const writeLimiter = rateLimit({
  windowMs: 60_000,
  max: config.WRITE_RATE_LIMIT,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'rate_limited', message: 'Too many requests. Please try again later.' },
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Health check (no auth, no rate limiting)
app.use('/api/v1/health', healthRouter);

// Bot management (auth required, rate limited)
// Apply auth to all bot routes, then split rate limiting by method
app.use('/api/v1/bots', auth, (req, _res, next) => {
  if (req.method === 'GET') {
    readLimiter(req, _res, next);
  } else {
    writeLimiter(req, _res, next);
  }
}, botsRouter);

// 404 for unmatched routes
app.use((_req, res) => {
  res.status(404).json({ error: 'not_found', message: 'Endpoint not found' });
});

// Global error handler (must be last)
app.use(errorHandler);

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
app.listen(config.PORT, '0.0.0.0', () => {
  logger.info(`OpenClaw API server listening on port ${config.PORT}`);
  logger.info(`Environment: ${config.NODE_ENV}`);
});
