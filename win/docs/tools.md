# Tools

All MCP tools return MCP `content` blocks. Errors set `isError: true` with a text explanation. Unless noted, call `activate` before sending text or keyboard shortcuts.

| Tool | Required parameters | Description |
|---|---|---|
| `list_apps` | none | List visible top-level Windows GUI windows with process names, PIDs, HWNDs, and titles. |
| `get_ax_tree` | `bundle_id` | Dump a numbered UI Automation tree. Optional: `max_depth`, `scope`. |
| `ax_tree_json` | `bundle_id` | Return the same UI tree as JSON. Optional: `max_depth`, `scope`. |
| `find_element` | `bundle_id`, `query` | Find first UI element matching `query` in name, automation id, class, value, or control type. |
| `click_element` | `bundle_id`, `query` | Click or invoke the first matching element. |
| `click_ref` | `ref` | Click `@eN` from the most recent tree call in the same MCP process. |
| `activate` | `bundle_id` | Bring target window to foreground. |
| `type_text` | `text` | Put text on clipboard and paste with `Ctrl+V`. |
| `key_press` | `key` | Send one key. Optional: `modifiers` array such as `ctrl`, `shift`, `alt`, `win`. |
| `wait_for` | `bundle_id`, `query` | Poll until the target element appears. Optional: `timeout`. |
| `scroll` | `dx` or `dy` | Send wheel event; optionally specify `bundle_id` and `query` to move cursor over an element first. |
| `right_click` | `bundle_id`, `query` | Context-click the first matching element. |
| `screenshot` | none | Capture full virtual screen, or target window if `bundle_id` is provided. Optional `return`: `path` or `base64`. |
| `menu` | `bundle_id`, `path` | Best-effort `MenuItem` search by the last segment of a slash-separated path. |
| `clip_get` | none | Read clipboard text. |
| `clip_set` | `text` | Replace clipboard text. |

## CLI equivalents

| MCP tool | CLI |
|---|---|
| `list_apps` | `wcu apps` |
| `get_ax_tree` | `wcu tree --bundle-id ...` |
| `ax_tree_json` | `wcu tree --bundle-id ... --json` |
| `find_element` | `wcu find --bundle-id ... --query ...` |
| `click_element` | `wcu click --bundle-id ... --query ...` |
| `activate` | `wcu activate --bundle-id ...` |
| `type_text` | `wcu type --text ...` |
| `key_press` | `wcu key --key ... --mods ctrl` |
| `wait_for` | `wcu wait --bundle-id ... --query ...` |
| `scroll` | `wcu scroll --dy -300` |
| `right_click` | `wcu rclick --bundle-id ... --query ...` |
| `screenshot` | `wcu shot` |
| `menu` | `wcu menu --bundle-id ... --path File/Open` |
| `clip_get` / `clip_set` | `wcu clip get` / `wcu clip set --text ...` |
