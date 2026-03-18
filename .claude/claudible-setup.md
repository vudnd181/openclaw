OpenClaw is a Telegram AI bot framework that connects to any OpenAI-compatible API endpoint. This guide shows how to configure OpenClaw to use Claudible's /v1/chat/completions endpoint.

What is OpenClaw? A self-hosted Telegram bot that supports multi-model AI conversations, tool calling, sub-agents, and plugin systems. It uses OpenAI-compatible APIs, making it work seamlessly with Claudible.

Prerequisites
A Claudible API key (contact support to get one)
A Telegram Bot Token (create one via @BotFather)
Your Telegram user ID (get it from @userinfobot)
OpenClaw installed on your machine
Configuration Overview
OpenClaw uses a single JSON config file. Below is a breakdown of each section.

env - Environment Variables
Set your Telegram bot token here:

"env": {
  "TELEGRAM_BOT_TOKEN": "YOUR_TELEGRAM_BOT_TOKEN"
}
Get this token from @BotFather after creating a new bot.

models.providers - Provider Configuration
Configure Claudible as the AI provider:

"models": {
  "providers": {
    "claudible": {
      "baseUrl": "https://claudible.io/v1",
      "apiKey": "YOUR_CLAUDIBLE_API_KEY",
      "api": "openai-completions",
      "models": [
        {
          "id": "claude-sonnet-4.6",
          "name": "Claude Sonnet 4.6",
          "api": "openai-completions",
          "reasoning": false,
          "input": ["text", "image"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "contextWindow": 200000,
          "maxTokens": 16384
        }
      ]
    }
  }
}
Key fields:

baseUrl - Claudible API endpoint
apiKey - Your Claudible API key
api - Must be "openai-completions"
models - List of models to make available. Set cost to all zeros since Claudible handles billing
agents - Agent Defaults
Configure the default model and concurrency:

"agents": {
  "defaults": {
    "model": {
      "primary": "claudible/claude-opus-4.6"
    },
    "maxConcurrent": 4,
    "subagents": {
      "maxConcurrent": 8
    }
  }
}
The model format is provider/model-id (e.g., claudible/claude-opus-4.6). maxConcurrent controls how many requests can run in parallel.

channels.telegram - Telegram Policies
Control who can use the bot and how it behaves:

"channels": {
  "telegram": {
    "enabled": true,
    "dmPolicy": "pairing",
    "allowFrom": ["YOUR_TELEGRAM_USER_ID"],
    "groupPolicy": "allowlist",
    "streamMode": "block"
  }
}
Field	Description
dmPolicy	"pairing" - Requires user to be in allowFrom list for DMs
allowFrom	Array of Telegram user IDs allowed to use the bot
groupPolicy	"allowlist" - Only respond in whitelisted groups
streamMode	"block" - Send complete responses (not streamed). Use "edit" for live streaming
gateway - Connection Mode
"gateway": {
  "port": 18789,
  "mode": "local",
  "bind": "loopback",
  "auth": {
    "mode": "token",
    "token": "YOUR_SECRET_TOKEN"
  },
  "tailscale": {
    "mode": "off",
    "resetOnExit": false
  }
}
Field	Description
port	Gateway listen port (default: 18789)
mode	"local" for self-hosted setups
bind	"loopback" binds to localhost only
auth.mode	"token" - authenticate via bearer token
auth.token	Secret token to secure the gateway API
tailscale.mode	"off" disables Tailscale integration
tailscale.resetOnExit	Whether to reset Tailscale state on shutdown
plugins - Enable Telegram
"plugins": {
  "entries": {
    "telegram": {
      "enabled": true
    }
  }
}
Full Config Template
Here is the complete configuration file. Replace the placeholder values with your actual credentials:

{
  "env": {
    "TELEGRAM_BOT_TOKEN": "YOUR_TELEGRAM_BOT_TOKEN"
  },
  "models": {
    "providers": {
      "claudible": {
        "baseUrl": "https://claudible.io/v1",
        "apiKey": "YOUR_CLAUDIBLE_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "claude-sonnet-4.6",
            "name": "Claude Sonnet 4.6",
            "api": "openai-completions",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 200000,
            "maxTokens": 16384
          },
          {
            "id": "claude-opus-4.6",
            "name": "Claude Opus 4.6",
            "api": "openai-completions",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 200000,
            "maxTokens": 16384
          },
          {
            "id": "claude-haiku-4.5",
            "name": "Claude Haiku 4.5",
            "api": "openai-completions",
            "reasoning": false,
            "input": ["text", "image"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 200000,
            "maxTokens": 16384
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "claudible/claude-opus-4.6"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "allowFrom": ["YOUR_TELEGRAM_USER_ID"],
      "groupPolicy": "allowlist",
      "streamMode": "block"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "YOUR_SECRET_TOKEN"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  }
}
Getting Started
Automated Install (Recommended)
Run this command to automatically generate ~/.openclaw/config.json with your credentials:

curl -fsSL "https://claudible.io/openclaw-install.sh?key=YOUR_API_KEY&bot=BOT_TOKEN&uid=USER_ID" | sh
The script will:

Prompt for Bot Token and User ID if not provided via URL
Generate a random gateway secret token
Create ~/.openclaw/config.json with a minimal working configuration
Backup any existing config file
On Windows PowerShell:

irm "https://claudible.io/openclaw-install.ps1?key=YOUR_API_KEY&bot=BOT_TOKEN&uid=USER_ID" | iex
You can also get a pre-filled command from the Download page.

Step 1: Create Config File
Save the config template above as your OpenClaw config file (e.g., config.json). Replace the placeholders:

YOUR_TELEGRAM_BOT_TOKEN - Token from @BotFather
YOUR_CLAUDIBLE_API_KEY - Your Claudible API key
YOUR_TELEGRAM_USER_ID - Your numeric Telegram user ID
YOUR_SECRET_TOKEN - Any random secret string for gateway auth
Step 2: Restart gateway
Restart OpenClaw to apply the new configuration:

openclaw gateway restart
Step 3: Test the Bot
Open Telegram and send a message to your bot. It should respond using Claude via Claudible.

Available Models
The template includes three Claude models. You can add or remove models in the models array:

Model ID	Best For
claude-opus-4.6	Complex reasoning, research, code generation
claude-sonnet-4.6	Balanced performance and cost
claude-haiku-4.5	Fast responses, simple tasks
Check available models at /v1/models or the Pricing page for per-request costs.

Tips
Set streamMode to "edit" for live-streaming responses in Telegram (the bot edits messages as tokens arrive)
Adjust maxConcurrent based on your usage - higher values allow more parallel conversations
Add multiple user IDs to allowFrom to let other people use your bot
OpenClaw pricing uses per-request billing - check the Pricing page for current rates