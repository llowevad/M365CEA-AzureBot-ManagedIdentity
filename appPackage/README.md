# Teams App Package — `appPackage/`

This is a **Custom Engine Agent (CEA)** app package for Microsoft Teams and M365 Copilot. It registers a bot-based agent — there is **no declarative agent** included. All intelligence lives in the upstream A2A orchestrator; this package simply registers the bot endpoint so Teams and M365 Copilot can route conversations to it.

## What This Package Is

- A **bot registration** manifest (v1.21) that tells Teams/M365 Copilot where to send messages
- A `copilotAgents.customEngineAgents` entry that surfaces the bot as a Custom Engine Agent in M365 Copilot
- Placeholder icons for sideloading

## What This Package Is NOT

- ❌ **Not a Declarative Agent** — there is no `declarativeAgent.json`, no instructions file, and no plugin definitions
- ❌ **Not a Message Extension** — no compose commands or search commands
- ❌ **Not a Tab App** — no web content pages

## Contents

| File | Purpose |
|------|---------|
| `manifest.json` | Teams app manifest v1.21 — bot registration + CEA entry |
| `color.png` | 192×192 color icon (generated placeholder) |
| `outline.png` | 32×32 outline icon (generated placeholder) |
| `build-package.ps1` | Builds sideload-ready .zip with token replacement |
| `generate-icons.ps1` | Generates minimal valid PNG placeholders |

## Manifest Structure

The manifest defines two key sections:

**`bots`** — Registers the bot with Teams across personal, team, and group chat scopes.

**`copilotAgents.customEngineAgents`** — Tells M365 Copilot this bot is a Custom Engine Agent (type: `"bot"`). This is what makes the agent discoverable in Copilot. Unlike a declarative agent, the CEA handles all conversation logic server-side via the M365 Agents SDK.

## Quick Start

```powershell
# 1. Generate placeholder icons (run once)
.\generate-icons.ps1

# 2. Build the sideload package
.\build-package.ps1 -BotAppId "<UAI-client-id>" -AppServiceName "<your-app-service>"

# 3. Sideload M365CEAProxy.zip into Teams
```

## Placeholder Tokens

The manifest uses `${{TOKEN}}` syntax (compatible with Teams Toolkit):

| Token | Value | Source |
|-------|-------|--------|
| `${{BOT_APP_ID}}` | User-Assigned Managed Identity client ID | Azure Portal → UAI → Client ID |
| `${{APP_SERVICE_NAME}}` | App Service resource name | Azure Portal → App Service → Overview |

## Icon Requirements

| Icon | Size | Format | Notes |
|------|------|--------|-------|
| `color.png` | 192×192 px | PNG | Full-color app icon, displayed in Teams store and app drawer |
| `outline.png` | 32×32 px | PNG | Transparent background, single color (white) outline. Used in chat headers |

### Replacing Placeholder Icons

For production, replace the generated solid-color placeholders with branded icons:
- Use [Teams App Icon Generator](https://developer.microsoft.com/en-us/microsoft-teams/app-icon-generator)
- Or create manually: color icon = 192px square, outline = 32px with transparent bg

## Sideloading Instructions

1. Run `build-package.ps1` with your actual values
2. Open Microsoft Teams
3. Go to **Apps** → **Manage your apps** → **Upload a custom app**
4. Select `M365CEAProxy.zip`
5. Add the bot to a personal chat, team, or group chat
