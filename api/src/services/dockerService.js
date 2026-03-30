'use strict';

const { execFile } = require('child_process');
const config = require('../config');

/**
 * Get the status of a Docker container by name.
 * Returns one of: 'running', 'exited', 'created', 'paused', 'restarting', 'dead', 'not_found'.
 */
function getContainerStatus(containerName) {
  return new Promise((resolve) => {
    execFile(
      'docker',
      ['inspect', '--format', '{{.State.Status}}', containerName],
      { timeout: config.DOCKER_INSPECT_TIMEOUT },
      (error, stdout) => {
        if (error) {
          resolve('not_found');
        } else {
          resolve(stdout.trim() || 'not_found');
        }
      },
    );
  });
}

/**
 * Get detailed container info via docker inspect.
 * Returns parsed JSON object or null if container doesn't exist.
 */
function getContainerDetails(containerName) {
  return new Promise((resolve) => {
    execFile(
      'docker',
      ['inspect', containerName],
      { timeout: config.DOCKER_INSPECT_TIMEOUT },
      (error, stdout) => {
        if (error) {
          resolve(null);
          return;
        }
        try {
          const data = JSON.parse(stdout);
          resolve(data[0] || null);
        } catch {
          resolve(null);
        }
      },
    );
  });
}

module.exports = { getContainerStatus, getContainerDetails };
