# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenClaw 一键安装包 (Windows 中国版) — a Windows installer and configuration manager for OpenClaw, an AI assistant framework. This is a distribution/onboarding package, not a compiled application. All scripts are PowerShell + Batch, with HTML tutorial guides.

Target: Chinese Windows users. All UI text is in Chinese.

## Running & Testing

There is no build step, test suite, or linter. The project consists of PowerShell scripts, Batch launchers, and HTML pages.

```powershell
# Run installer directly (requires admin):
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

# Via batch launcher (handles UAC elevation automatically):
# Double-click 一键安装.bat

# Configuration tools:
powershell -NoProfile -ExecutionPolicy Bypass -File configure-api.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File configure-feishu.ps1

# Build distributable .exe (requires Inno Setup installed):
# Open OpenClawInstaller.iss in Inno Setup IDE → Compile
```

## Architecture

### Installation Flow (6 Steps in install.ps1)

1. Check/install Node.js >= 22 (from npmmirror.com)
2. Check/install Git (from npmmirror.com)
3. Configure npm domestic mirror + `npm install -g openclaw`
4. Configure AI provider (dual-window: browser opens provider site + local HTML tutorial)
5. Configure Feishu bot (dual-window: browser + local tutorial)
6. Write config to `~/.openclaw/openclaw.json` + start OpenClaw

### Chinese Path Workaround

`.bat` launchers copy `.ps1` scripts and `guides/` to `%TEMP%` before execution to avoid Unicode/Chinese path issues in PowerShell. The original directory is saved in `%TEMP%\openclaw-original-dir.txt` so scripts can locate resources.

### Key Files

| File | Role |
|------|------|
| `install.ps1` | Main 6-step installation wizard (~800 lines) |
| `configure-api.ps1` | API provider management (add/switch/test providers) |
| `configure-feishu.ps1` | Feishu bot configuration |
| `uninstall.ps1` | Cleanup and restoration of previous Claude Code settings |
| `一键安装.bat` | Entry point with UAC elevation logic |
| `OpenClawInstaller.iss` | Inno Setup packaging script for .exe distribution |
| `guides/*.html` | Step-by-step tutorial pages with screenshots |

### Configuration

User config is stored at `~/.openclaw/openclaw.json` with this structure:

```json
{
  "models": {
    "providers": {
      "<provider>": {
        "baseUrl": "https://...",
        "apiKey": "sk-...",
        "models": [{ "id": "...", "name": "...", "context": 128000, "maxTokens": 32768 }]
      }
    }
  },
  "channels": {
    "feishu": {
      "accounts": {
        "main": { "appId": "cli_xxx", "appSecret": "xxx", "botName": "..." }
      }
    }
  }
}
```

### Supported AI Providers

All three use Anthropic-compatible API format (`/v1/messages`), no proxy needed in China:

- **智谱 GLM** — `https://open.bigmodel.cn/api/anthropic` (recommended, has free tier: glm-4-flash)
- **Kimi** — `https://api.moonshot.cn/anthropic` (256K context with kimi-k2.5)
- **MiniMax** — `https://api.minimax.io/anthropic`

### Claude Code Integration

The installer detects and preserves existing `~/.claude/settings.json`. On uninstall, previous settings are restored from backup.

## Conventions

- All user-facing text must be in Chinese
- Use domestic mirrors (npmmirror.com) for all downloads — never use direct international URLs
- PowerShell scripts must work with `-ExecutionPolicy Bypass` and handle paths with Chinese characters
- API key validation uses `Test-ApiKey` function (sends a test request to the provider's `/v1/messages` endpoint)
- Batch launchers must handle UAC elevation and Chinese path copying to `%TEMP%`
