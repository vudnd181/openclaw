# Auto-Approve Device Pairing

## Overview

When a browser first connects to an OpenClaw bot dashboard, the bot requires **device pairing** — a security step where the bot must approve the new device before granting access.

Without automation, this requires two manual commands:

```bash
# 1. List pending device requests
docker exec -u node openclaw-bot-<name> /usr/local/bin/openclaw devices list

# 2. Approve each request by ID
docker exec -u node openclaw-bot-<name> /usr/local/bin/openclaw devices approve <REQUEST_ID>
```

`auto-approve.sh` automates this entire flow.

## Usage

### Single Bot — Approve Pending Devices Now

```bash
./auto-approve.sh vu
```

Checks for pending device requests and approves them immediately. If none found, exits.

### Single Bot — Wait for Browser Connection

```bash
./auto-approve.sh vu --wait
```

Polls every 3 seconds for up to 60 seconds, waiting for a browser to connect. Once a device request appears, it auto-approves and exits.

### All Bots — Background Daemon

```bash
./auto-approve.sh --all
```

Runs forever, monitoring **all bots** in `.port-registry`. Checks every 5 seconds and auto-approves any pending device requests across all bots.

To run as a background daemon (persists after SSH disconnect):

```bash
nohup ./auto-approve.sh --all > /var/log/auto-approve.log 2>&1 &
```

## Integration with deploy-bot.sh

When deploying a new bot via `deploy-bot.sh`, auto-approve is triggered automatically:

```
./deploy-bot.sh alice 123:ABC 658635669
     │
     ├── Build & start container
     ├── Reload nginx
     ├── Health check (wait up to 30s)
     │
     └── auto-approve.sh alice --wait    ← runs automatically
              │
              ├── Shows gateway token + dashboard URL
              ├── Waits for browser connection (60s timeout)
              ├── Detects device pairing request
              └── Auto-approves
```

The deployer just needs to open the dashboard URL in a browser during the 60-second window.

## Output

### Gateway Info (shown on every run)

```
🔑 Bot 'vu':
   Token: a1b2c3d4e5f6...
   Dashboard: https://vu.dashboard.clawopen.vn
```

### Daemon Mode

```
🤖 Auto-approve daemon started
   Monitoring ALL bots for device pairing requests
   Checking every 5 seconds
   Press Ctrl+C to stop

🔑 Bot 'vu':
   Token: a1b2c3d4e5f6...
   Dashboard: https://vu.dashboard.clawopen.vn
🔑 Bot 'alice':
   Token: f6e5d4c3b2a1...
   Dashboard: https://alice.dashboard.clawopen.vn

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[14:32:15] ✅ [vu] Approved device: abc123-def456
[14:35:42] ✅ [alice] Approved device: 789ghi-012jkl
```

## How It Works

1. Reads bot list from `bots/.port-registry`
2. For each bot, runs `openclaw devices list` inside the container
3. Extracts pending request IDs from the output
4. Runs `openclaw devices approve <ID>` for each pending request
5. In daemon mode (`--all`), repeats every 5 seconds indefinitely
