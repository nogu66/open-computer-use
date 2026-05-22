---
name: open-computer-use
description: Use whenever the user wants to control a real desktop GUI app through MCP or CLI. On Windows use Microsoft UI Automation via scripts/ocu-windows.ps1; on macOS use the Swift Accessibility API binary. Prefer when login state, cookies, SSO, passkeys, extensions, or native app state matter.
---

# open-computer-use (`ocu`)

Desktop computer use through native accessibility APIs.

- Windows: PowerShell + Microsoft UI Automation (`scripts/ocu-windows.ps1`)
- macOS: Swift + Accessibility API + CGEvent + `screencapture`

## Windows

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-test-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --app-id chrome --depth 8
```

Windows MCP is launched with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\mcp-server.ps1
```

Use `app_id`, `process_name`, `pid`, or `title`. `bundle_id` is still accepted as
an alias for clients that reuse the macOS schema.

## Core workflow

1. `list_apps` / `apps` to identify the target.
2. `activate` before typing.
3. `get_ax_tree` / `tree` or `ax_tree_json` to inspect visible UI.
4. Use `click_element`, `click_ref`, `type_text`, `key_press`, `wait_for`, and `screenshot`.
5. Verify visually when labels are ambiguous.

## Windows safety policy

The Windows path blocks destructive typed commands, unsafe paste, Enter after an
unsafe key-by-key command, and delete-like UI labels by default.

Unsafe override requires both `OCU_ALLOW_UNSAFE_INPUT=1` and
`allow_unsafe=true`.

Repository: https://github.com/nogu66/open-computer-use
