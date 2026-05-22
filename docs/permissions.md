# Permissions

`ocu` controls the Mac like assistive technology: it reads the accessibility
tree and posts low-level events. macOS gates that behind explicit user consent.

On Windows, this fork uses Microsoft UI Automation from Windows PowerShell. It
does not need a separate install-time permission prompt, but it is still bound
by Windows integrity and session boundaries. It may not control elevated apps
from a non-elevated agent, apps running as a different user, protected system
surfaces, or controls that do not expose a useful UI Automation tree.

## Accessibility (required)

**Used for:** `get_ax_tree`, `find_element`, `click_element`, `click_ref`,
`activate`, `wait_for`, `scroll`, `right_click`, `menu`, and any tool that
queries or acts on UI elements.

**Enable:**

1. Open **System Settings → Privacy & Security → Accessibility**
2. Enable the app that **launches** `ocu`:
   - Claude Code, Cursor, Codex CLI, Terminal, Ghostty, iTerm, etc.
3. If you run `ocu` directly from Terminal, enable **Terminal** (or your terminal app).

**First run:** `ocu` calls `AXIsProcessTrustedWithOptions` with the system prompt
flag so macOS may show a dialog. You can also open the pane manually with:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

**Troubleshooting:**

| Symptom | Likely cause |
|---|---|
| `Accessibility permission not granted` in tool output | Parent process not listed / toggle off |
| Empty or tiny AX tree | Target app blocks AX (`AXEnhancedUserInterface` helps; `ocu` sets it) |
| Clicks go to the wrong app | Forgot `activate` before `type_text` / `key_press` |
| Permission granted but still fails | Rebuild renamed the binary; remove and re-add the host app |

`ocu` enables `AXEnhancedUserInterface` and `AXManualAccessibility` on the
target app before walking the tree (same technique many automation tools use).

## Screen Recording (screenshot only)

**Used for:** `screenshot` when capturing a window or full screen via `screencapture`.

**Enable:** System Settings → Privacy & Security → **Screen Recording** → same
host process as above.

CLI `ocu shot` uses the same code path. Other tools do not need this permission.

## What we do *not* need

- **Automation** (Apple Events) — not used
- **Input Monitoring** — CGEvent posting does not require it on current macOS for our use case
- **Full Disk Access** — not used

## Security notes for operators

- Any process with Accessibility can observe and manipulate **all** GUI apps.
- Only register `ocu` with MCP clients you trust.
- Tool output may include window titles, field values, and clipboard text — treat logs as sensitive.

## CI / headless environments

GitHub Actions runners do not grant Accessibility to test jobs. Unit tests in
`OCUCoreTests` avoid AX APIs entirely. End-to-end verification is a maintainer
or developer machine concern after manual permission setup.
