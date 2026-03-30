'use strict';

const lockfile = require('proper-lockfile');
const config = require('../config');
const { logger } = require('../middleware/requestLogger');

/**
 * Execute a function while holding an exclusive lock on .port-registry.
 * Prevents concurrent deploy/remove operations from racing on port assignment.
 *
 * Throws a 503-style error if the lock cannot be acquired after retries.
 */
async function withPortRegistryLock(fn) {
  let release;

  try {
    release = await lockfile.lock(config.PORT_REGISTRY, {
      retries: {
        retries: 5,
        minTimeout: 500,
        maxTimeout: 3000,
        factor: 2,
      },
      stale: 120_000, // consider lock stale after 2 min (matches deploy timeout)
    });
  } catch (err) {
    logger.error({ message: 'Failed to acquire port registry lock', error: err.message });
    const lockErr = new Error(
      'Server is busy processing another bot operation. Please retry shortly.',
    );
    lockErr.statusCode = 503;
    lockErr.code = 'busy';
    throw lockErr;
  }

  try {
    return await fn();
  } finally {
    if (release) {
      try {
        await release();
      } catch (err) {
        logger.warn({ message: 'Failed to release lock', error: err.message });
      }
    }
  }
}

module.exports = { withPortRegistryLock };
