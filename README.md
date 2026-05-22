# OpenComputerUse

<a href="README.ja.md">日本語</a>

**Desktop computer use for AI agents** - control the apps you already have open (logged-in Chrome, Slack, native apps) via native accessibility APIs, exposed as an MCP stdio server and a small CLI.

This repository keeps the original macOS Accessibility API path and adds a Windows
path based on Microsoft UI Automation. Windows input is guarded by default:
dangerous shell text, recursive deletion, file modification commands, encoded
PowerShell, and delete-like UI labels are blocked unless the operator explicitly
enables the two-step unsafe override.

Inspired by [Codex Computer Use](https://developers.openai.com/codex/app/computer-use): same idea (OS-level AX + CGEvent, not CDP), packaged for Claude Code, Cursor, Codex, and any MCP client.

| | Playwright / CDP | **open-computer-use (`ocu`)** |
|---|---|---|
| Uses your logged-in Chrome profile | Usually no (separate profile) | **Yes** — operates the real app |
| Cookie / SSO / extensions | Often lost | **Preserved** |
| `navigator.webdriver` | May be set | **Not applicable** (not in the browser) |
| Platform | Cross-platform | **Windows 10/11 + macOS 13+** |

## Windows quick start

From this checkout on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-test-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --depth 1 --max-nodes 20
```

Cursor is wired by `.cursor/mcp.json`. Codex/plugin MCP uses `.mcp.json`.
Both call `scripts/mcp-server.ps1`, which starts the PowerShell/MS UI Automation
server. macOS configs are kept as `.cursor/mcp.macos.json` and `.mcp.macos.json`.

See [docs/windows-msuia.md](docs/windows-msuia.md) for Windows setup, safety
policy details, and Codex/Cursor JSON snippets.

## Install (recommended)

Install the latest **release binary** to `~/.local/bin/ocu`:

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
```

From a checkout:

```bash
./scripts/install.sh              # latest GitHub Release (falls back to source build)
./scripts/install.sh --version v0.1.0
./scripts/install.sh --from-source  # SwiftPM build only
```

Ensure `~/.local/bin` is on your `PATH`, then wire MCP:

```bash
claude mcp add open-computer-use -- $(which ocu)
```

## Install as a plugin

This repository also ships as a plugin for **Claude Code**, **Codex**, and **Cursor** (skill + MCP config). Install the binary first (above), then add the plugin so agents get the skill and MCP wiring.

### Claude Code

```bash
/plugin marketplace add nogu66/open-computer-use
/plugin install open-computer-use@open-computer-use
/reload-plugins
```

The plugin bundles the `open-computer-use` skill and an MCP server (`open-computer-use`).

### Codex

```bash
codex plugin marketplace add nogu66/open-computer-use
# then install open-computer-use from the plugin directory in Codex
```

Repo-scoped marketplace file: [`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json).  
Codex-native manifest: [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json).

### Cursor

Clone or open this repo in Cursor. Project-level config is included:

- MCP: [`.cursor/mcp.json`](.cursor/mcp.json) -> `scripts/mcp-server.ps1` on Windows. The macOS config is kept as [`.cursor/mcp.macos.json`](.cursor/mcp.macos.json).
- Skill: [`.cursor/skills/open-computer-use/SKILL.md`](.cursor/skills/open-computer-use/SKILL.md)

Restart Cursor or reload MCP. On macOS, use `.cursor/mcp.macos.json`; `mcp-server.sh` can auto-install the latest release if `ocu` is missing.

For other projects, copy the skill to `~/.cursor/skills/open-computer-use/`. On Windows, point MCP at `scripts/mcp-server.ps1` with `powershell.exe`. On macOS, point MCP at `scripts/mcp-server.sh` from your checkout, or at `$(which ocu)` after `./scripts/install.sh`.

See [examples/plugin-install.md](examples/plugin-install.md) for details and troubleshooting.

## Quick start (manual build)

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ (Xcode 15+) only if building from source
- **Accessibility** permission for the process that launches `ocu` (Terminal, Ghostty, Claude Code, Cursor, …)

### Build from source

```bash
git clone https://github.com/nogu66/open-computer-use.git
cd open-computer-use
./scripts/install.sh --from-source
ocu --version
```

### MCP setup (manual)

```bash
claude mcp add open-computer-use -- $(which ocu)
# or, from a dev checkout (auto-installs latest release on first MCP start):
claude mcp add open-computer-use -- ./scripts/mcp-server.sh
```

Restart Claude Code. You should see tools like `mcp__open-computer-use__list_apps`, `get_ax_tree`, `click_element`, etc.

See [examples/](examples/) for Cursor, Codex, and raw `mcp.json` snippets.

### CLI smoke test

```bash
ocu apps
ocu activate --bundle-id com.google.Chrome
ocu tree --bundle-id com.google.Chrome --depth 6
ocu click --bundle-id com.google.Chrome --query "Search"
```

Run the MCP protocol smoke test (no UI permissions required for `list_apps`):

```bash
./scripts/smoke-test.sh
```

## Permissions

| Permission | Required for | Where to enable |
|---|---|---|
| **Accessibility** | AX tree, clicks, keys, menus | System Settings → Privacy & Security → Accessibility |
| **Screen Recording** | `screenshot` (window capture via `screencapture`) | System Settings → Privacy & Security → Screen Recording |

Grant access to the **parent app** that spawns `ocu` (e.g. Claude Code), not only the `ocu` binary. Details: [docs/permissions.md](docs/permissions.md).

## MCP tools

| Tool | Summary |
|---|---|
| `list_apps` | Running GUI apps (name, bundle ID, PID) |
| `get_ax_tree` | Numbered AX tree text for an app/window |
| `ax_tree_json` | Same tree as JSON (`ref`, `role`, `children`, …) |
| `find_element` | Locate first element matching a substring |
| `click_element` / `click_ref` | Click by query or `@eN` ref from last tree |
| `activate` | Bring app to foreground (call before typing) |
| `type_text` / `key_press` | Unicode typing and key combos |
| `wait_for` | Poll until an element appears |
| `scroll` / `right_click` | Wheel and context menu |
| `screenshot` | PNG path or base64 |
| `menu` | Menubar path, e.g. `File/Open` |
| `clip_get` / `clip_set` | Clipboard text |

Full schemas and agent tips: [docs/tools.md](docs/tools.md).

## Recommended agent workflow

1. `list_apps` — find `bundle_id` (e.g. `com.google.Chrome`)
2. `activate` — focus the app so keystrokes do not leak elsewhere
3. `get_ax_tree` or `ax_tree_json` — understand visible UI
4. `click_element` / `click_ref` / `type_text` / `key_press` — act
5. `wait_for` — bridge async page loads
6. `screenshot` — verify visually when AX text is ambiguous

## Architecture

```
Your agent (Claude / Codex / Cursor / …)
        │  MCP JSON-RPC over stdio
        ▼
   ocu (Swift)
   ├── AXUIElement     read UI tree, AXPress, menus
   ├── CGEvent         mouse, keyboard, scroll
   └── screencapture   screenshots
        │
        ▼
User's real apps (Chrome with login, etc.)
```

More detail: [docs/architecture.md](docs/architecture.md).

## Development

```bash
swift build && swift test
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Releases

Tagged releases (`v*.*.*`) publish a universal macOS binary tarball via GitHub Actions. See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).

## Related research

This repo was extracted from browser-agent research comparing Accessibility-based control vs Chrome extension / Playwright approaches. The investigation notes live in the parent [browser-agent-research](https://github.com/nogu66/browser-agent-research) workspace (Japanese).
