---
name: open-computer-use
description: Use whenever the user wants to control a macOS GUI app — clicking buttons, reading on-screen content, typing into open windows, or operating their logged-in browser. Triggers on "Chrome を操作", "ログイン済みのブラウザで", "Mac アプリを動かして", "ocu", "computer use", "operate the browser". Prefer over Playwright when login state, cookies, SSO, passkeys, or extensions matter.
---

# open-computer-use (`ocu`)

macOS Accessibility API + CGEvent + `screencapture` packaged as one CLI/MCP binary. Model-agnostic: works from any agent that can call Bash or MCP.

## Install (latest release)

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
ocu --version
```

Pinned version: `OCU_VERSION=v0.1.0 ./scripts/install.sh`  
Source build only: `./scripts/install.sh --from-source`

## Binary resolution

When installed as a plugin, prefer the bundled wrapper:

```bash
OCU="${CLAUDE_PLUGIN_ROOT}/scripts/ocu-cli.sh"
# Codex also sets PLUGIN_ROOT; Cursor project checkout:
# OCU="$(git rev-parse --show-toplevel)/scripts/ocu-cli.sh"
```

After install:

```bash
OCU="$(command -v ocu)"
```

Wrappers auto-install the latest release to `~/.local/bin/ocu` on first use unless `OCU_SKIP_AUTO_INSTALL=1`.

## When to use

- Logged-in Chrome, Gmail, Notion, Slack, banking sites
- Native Mac apps without APIs (Notes, System Settings, etc.)
- Reading what is actually on screen
- Avoiding bot detection (no CDP, no new browser profile)

## When not to use

- Fresh-profile scraping only → Playwright
- Public HTML fetch only → WebFetch / curl
- Service has a stable API → use the API

## Core workflow

```bash
$OCU apps
$OCU activate --bundle-id com.google.Chrome
$OCU tree --bundle-id com.google.Chrome --depth 8
$OCU click --bundle-id com.google.Chrome --query "Address and search bar"
$OCU type --text "https://example.com"
$OCU key --key return
$OCU shot --bundle-id com.google.Chrome --out /tmp/after.png
```

## Subcommands

| Command | Purpose |
|---|---|
| `apps` | List GUI apps (bundle ID + PID) |
| `activate --bundle-id <id>` | Bring app to front (**call first**) |
| `tree --bundle-id <id> [--depth N]` | AX tree; add `--json` for structured output |
| `find --bundle-id <id> --query <q>` | Substring match on AX labels |
| `wait --bundle-id <id> --query <q> [--timeout SEC]` | Poll until element appears |
| `click` / `rclick` | Left / right click by `--query` |
| `type --text <s>` | Type into focused field |
| `key --key <name> [--mods cmd,shift,alt,ctrl]` | Key press |
| `scroll` | Scroll at element or cursor |
| `menu --bundle-id <id> --path <p>` | Menubar path, e.g. `"File/New Tab"` |
| `shot [--bundle-id <id>] [--out <path>]` | Screenshot PNG |
| `clip get` / `clip set --text <s>` | Clipboard |

## MCP vs CLI

Same binary. Plugin install exposes MCP tools (`list_apps`, `get_ax_tree`, `click_element`, …). Bash agents use the CLI subcommands above.

Direct MCP (no wrapper):

```bash
claude mcp add open-computer-use -- $(command -v ocu)
```

## Pitfalls

- Always `activate` first — otherwise `type`/`key` leak to the terminal
- Prefer `menu` over `Cmd+T` when Chrome is playing video (keys may be captured)
- `find`/`click` return the first match — narrow queries or inspect `tree` first
- CLI mode has no `@eN` refs — use `--query` (MCP `click_ref` uses refs from last tree)
- Grant **Accessibility** (and **Screen Recording** for screenshots) to the parent app (Claude Code, Cursor, Codex, Terminal)

Repository: https://github.com/nogu66/open-computer-use
