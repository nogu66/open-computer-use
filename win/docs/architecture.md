# Architecture

`win-computer-use` は、macOS向け `open-computer-use` の設計を Windows に移植したものです。中核思想は、ブラウザ自動化プロトコルではなく **実ユーザーセッション内の実アプリ** を、OSのアクセシビリティ層と合成入力で制御することにあります。

```text
Your agent / MCP client
        │
        │ MCP JSON-RPC over stdio
        ▼
   wcu.exe (.NET 8 / C#)
   ├── Microsoft UI Automation   read UI tree, InvokePattern, ValuePattern
   ├── Win32 window APIs         list windows, foreground activation, rectangles
   ├── Win32 mouse input         click, right-click, wheel scroll
   ├── Windows Forms SendKeys    keyboard shortcuts and paste
   ├── Windows Clipboard         text clipboard get/set
   └── GDI+ CopyFromScreen       screenshots
        │
        ▼
User's real Windows apps
```

## Execution modes

`wcu` has two execution modes. When started as `wcu serve`, it runs as an MCP stdio server. When started with another subcommand, it runs as a regular CLI. This mirrors the reference implementation and allows the same binary to be used both directly by developers and indirectly by LLM agents.

| Mode | Example | Purpose |
|---|---|---|
| MCP server | `wcu serve` | Long-running tool server for Claude/Cursor/Codex-style MCP clients |
| CLI | `wcu tree --bundle-id chrome` | Debugging, scripting, and manual smoke tests |

## Target resolution

macOS has stable bundle identifiers such as `com.google.Chrome`. Windows does not have an exact equivalent for all desktop apps, so `bundle_id` is treated as a compatibility name rather than a literal bundle identifier.

| Input | Resolution rule |
|---|---|
| `pid:1234` | Match the top-level window whose owning process ID is `1234` |
| `chrome` | Match `Process.ProcessName` case-insensitively |
| `Untitled - Notepad` | Match visible top-level window title by substring |

The resolved top-level window handle is converted to an `AutomationElement` with `AutomationElement.FromHandle(hwnd)`. The initial implementation scopes tree traversal to the window because this is safer and faster than traversing the entire desktop.

## UI tree and refs

`get_ax_tree` and `ax_tree_json` traverse UIA children breadth-first/recursively and assign process-local refs such as `@e1`, `@e2`, and `@e3`. These refs are stored in memory and invalidated when another tree command runs, matching the behavior of `open-computer-use`.

Each node may expose the following information:

| Field | Source |
|---|---|
| `name` | `AutomationElement.Current.Name` |
| `control_type` | `AutomationElement.Current.ControlType` |
| `automation_id` | `AutomationElement.Current.AutomationId` |
| `class_name` | `AutomationElement.Current.ClassName` |
| `process_id` | `AutomationElement.Current.ProcessId` |
| `value` | `ValuePattern.Current.Value` when supported |
| `rectangle` | `AutomationElement.Current.BoundingRectangle` |

## Action strategy

For semantic actions, `wcu` first tries UIA patterns. If no semantic action is available, it falls back to coordinate input at the center of the element rectangle.

| Operation | Preferred method | Fallback |
|---|---|---|
| Click | `InvokePattern.Invoke()` | left mouse click at bounding-rectangle center |
| Select | `SelectionItemPattern.Select()` | left mouse click |
| Expand/collapse | `ExpandCollapsePattern` | left mouse click |
| Text input | Clipboard + `Ctrl+V` | future: low-level `SendInput` Unicode events |
| Keyboard shortcut | `SendKeys.SendWait()` | future: low-level `SendInput` virtual keys |
| Scroll | Win32 mouse wheel | none |

## Security and permission model

Unlike macOS Accessibility, Windows UI Automation generally does not show a global user approval dialog for normal desktop apps. The more important boundary is **integrity level**. A non-elevated process cannot reliably drive an elevated administrator application. If the target app is elevated, `wcu` should also be launched as administrator.

This tool can observe window titles, UI text, field values, and clipboard contents. When exposed as MCP, the client agent effectively gains the ability to inspect and manipulate the user's desktop session. It should therefore be registered only with trusted agent clients.
