'use strict';

const router = require('express').Router();

router.get('/', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: require('../../package.json').version,
  });
});

module.exports = router;
