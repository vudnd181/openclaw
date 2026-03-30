'use strict';

const { execFile } = require('child_process');
const config = require('../config');

/**
 * Execute a shell script and return { stdout, stderr, output }.
 * Rejects with an error that includes exitCode and output on failure.
 */
function runScript(scriptPath, args = [], options = {}) {
  return new Promise((resolve, reject) => {
    execFile(
      scriptPath,
      args,
      {
        cwd: options.cwd || config.WORKSPACE,
        timeout: options.timeout || 60_000,
        env: { ...process.env, ...options.env },
        maxBuffer: 2 * 1024 * 1024, // 2 MB
        shell: '/bin/bash',
      },
      (error, stdout, stderr) => {
        const output = (stdout || '') + (stderr || '');

        if (error) {
          const err = new Error(`Script failed: ${error.message}`);
          err.exitCode = error.code;
          err.signal = error.signal;
          err.killed = error.killed;
          err.output = output.trim();
          reject(err);
        } else {
          resolve({
            stdout: (stdout || '').trim(),
            stderr: (stderr || '').trim(),
            output: output.trim(),
          });
        }
      },
    );
  });
}

module.exports = { runScript };
