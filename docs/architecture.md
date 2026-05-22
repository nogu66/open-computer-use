# Architecture

open-computer-use (`ocu`) is a single Swift executable that can run in two modes:

| Mode | Invocation | stdout |
|---|---|---|
| **MCP server** | no args, or `ocu serve` | JSON-RPC lines only |
| **CLI** | `ocu <subcommand> …` | human text or `--json` |

Logging always goes to **stderr** (`[ocu] …`) so MCP framing on stdout stays intact.

## Module split

```
Package.swift
├── OCUCore          (library, no AppKit / AX — CI-testable)
│   ├── Version.swift
│   ├── CLIArgs.swift
│   └── JSONRPC.swift
└── ocu              (executable — all macOS-specific code)
    └── main.swift   (~900 lines, intentional monolith)
```

Permission-sensitive code lives only in `Sources/ocu/main.swift`. Pure helpers
belong in `OCUCore` with matching tests under `Tests/OCUCoreTests/`.

## Control flow (MCP)

```mermaid
sequenceDiagram
    participant Agent as MCP client
    participant OCU as ocu
    participant AX as AXUIElement
    participant CG as CGEvent

    Agent->>OCU: initialize
    OCU-->>Agent: capabilities + serverInfo
    Agent->>OCU: tools/list
    OCU-->>Agent: tool schemas
    Agent->>OCU: tools/call (e.g. get_ax_tree)
    OCU->>AX: copy attribute tree
    AX-->>OCU: roles, titles, children
    OCU-->>Agent: numbered text tree + ref map
    Agent->>OCU: tools/call (click_ref)
    OCU->>AX: AXPress or CGEvent click
    OCU-->>Agent: result text
```

## Element references (`@eN`)

`get_ax_tree` and `ax_tree_json` populate an in-process `refMap: [Int: AXUIElement]`.
Refs are **invalidated** on the next tree dump for the same process. Agents should
either:

- re-fetch the tree before `click_ref`, or
- use `click_element` / `find_element` with a stable substring query.

## Input synthesis

| Action | Primary path | Fallback |
|---|---|---|
| Click | `AXPress` on element | `CGEvent` left click at element center |
| Right click | — | `CGEvent` right button at center |
| Type | `CGEvent` Unicode keystrokes | — |
| Key combo | `CGEvent` virtual key + flags | — |
| Scroll | `CGEvent` scroll wheel | optional focus point from element center |

## Screenshots

`screenshot` shells out to `/usr/sbin/screencapture`. When `bundle_id` is set,
the tool resolves the app's main window via `CGWindowListCopyWindowInfo` and
captures that window. This requires **Screen Recording** permission in addition
to Accessibility for some macOS versions.

## Why not CDP / Playwright?

CDP attaches to a browser process and sees the DOM. `ocu` never enters the
browser — it sees the same AX tree as VoiceOver and sends the same events a
human would. That is why a normal, logged-in Chrome session works without
exporting cookies or launching a second profile.

Trade-offs:

- Slower and noisier than DOM selectors for web-only tasks
- Substring search can match the wrong element when labels repeat
- macOS-only; no Linux/Windows support planned

## CI vs local dev

GitHub Actions runs `swift build` and `swift test` on `macos-14` and `macos-15`.
Tests cover `OCUCore` only. Integration tests that require Accessibility are not
run in CI; use `./scripts/smoke-test.sh` locally after granting permissions.
