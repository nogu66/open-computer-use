# OpenComputerUse

<p align="right">
  <a href="README.ja.md"><img src="https://img.shields.io/badge/日本語-README.ja.md-007ACC?style=for-the-badge" alt="日本語版 README"></a>
</p>

**macOS computer use for AI agents** — control the apps you already have open (logged-in Chrome, Slack, native apps) via the Accessibility API and synthetic input, exposed as an MCP stdio server and a small CLI.

Inspired by [Codex Computer Use](https://developers.openai.com/codex/app/computer-use): same idea (OS-level AX + CGEvent, not CDP), packaged for Claude Code, Cursor, Codex, and any MCP client.

| | Playwright / CDP | **OpenComputerUse (ocu)** |
|---|---|---|
| Uses your logged-in Chrome profile | Usually no (separate profile) | **Yes** — operates the real app |
| Cookie / SSO / extensions | Often lost | **Preserved** |
| `navigator.webdriver` | May be set | **Not applicable** (not in the browser) |
| Platform | Cross-platform | **macOS 13+ only** |

## Quick start

### Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ (Xcode 15+) to build from source
- **Accessibility** permission for the process that launches `ocu` (Terminal, Ghostty, Claude Code, Cursor, …)

### Build from source

```bash
git clone https://github.com/nogu66/OpenComputerUse.git
cd OpenComputerUse
swift build -c release
.build/release/ocu --version
```

Or use the install helper:

```bash
./scripts/install.sh          # builds release → ~/.local/bin/ocu
```

### MCP setup (Claude Code)

```bash
claude mcp add opencomputeruse -- $(which ocu)
# or, from a dev checkout:
claude mcp add opencomputeruse -- swift run -c release --package-path /path/to/OpenComputerUse ocu
```

Restart Claude Code. You should see tools like `mcp__opencomputeruse__list_apps`, `get_ax_tree`, `click_element`, etc.

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
