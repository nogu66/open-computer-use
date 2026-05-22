# MCP tool reference

All tools return MCP `content` blocks. Errors set `isError: true` with a text
explanation. Unless noted, call `activate` on the target app before typing keys.

On Windows, the same MCP tool names are served by `scripts/ocu-windows.ps1` using
Microsoft UI Automation. Windows accepts `app_id`, `process_name`, `pid`, and
`title`; `bundle_id` remains accepted as an alias for MCP clients already shaped
around the macOS schema. See [windows-msuia.md](windows-msuia.md).

## `list_apps`

List running applications with `NSWorkspace` (regular apps only).

| Parameter | Type | Required | Description |
|---|---|---|---|
| — | — | — | No parameters |

**Example:** discover Chrome → `com.google.Chrome`

---

## `get_ax_tree`

Dump a **numbered text tree** of the accessibility hierarchy. Each line is
`@eN role "title" …`. Use refs with `click_ref`.

| Parameter | Type | Required | Default |
|---|---|---|---|
| `bundle_id` | string | yes | — |
| `max_depth` | integer | no | `12` |
| `scope` | string | no | `window` (`window` or `app`) |

**Agent tip:** Start with `max_depth` 8–12; increase if the control you need is missing.

---

## `ax_tree_json`

Same walk as `get_ax_tree`, but returns one JSON object:

```json
{ "ref": 1, "role": "…", "title": "…", "children": [ … ] }
```

Parameters identical to `get_ax_tree`. Populates the same `refMap` as the text tree.

---

## `find_element`

Substring search across description, title, value, help, role fields. Returns
metadata only (does not click).

| Parameter | Type | Required |
|---|---|---|
| `bundle_id` | string | yes |
| `query` | string | yes |

---

## `click_element`

`find_element` + click. Prefers `AXPress`; falls back to center click via CGEvent.

| Parameter | Type | Required |
|---|---|---|
| `bundle_id` | string | yes |
| `query` | string | yes |

---

## `click_ref`

Click `@eN` from the **most recent** `get_ax_tree` / `ax_tree_json` in this process.

| Parameter | Type | Required |
|---|---|---|
| `ref` | integer | yes |

---

## `activate`

Bring app to foreground (`NSRunningApplication.activate`).

| Parameter | Type | Required |
|---|---|---|
| `bundle_id` | string | yes |

---

## `type_text`

Type Unicode into the **currently focused** field (system-wide focus).

| Parameter | Type | Required |
|---|---|---|
| `text` | string | yes |

---

## `key_press`

Send one key, optionally with modifiers.

| Parameter | Type | Required |
|---|---|---|
| `key` | string | yes |
| `modifiers` | string[] | no |

Supported keys include `return`, `tab`, `space`, `escape`, arrows, letters,
digits. Modifiers: `cmd`, `shift`, `alt`, `ctrl` (aliases accepted).

**Example:** focus URL bar — `key_press` with `key=l`, `modifiers=["cmd"]` after `activate`.

---

## `wait_for`

Poll until `find` succeeds or timeout.

| Parameter | Type | Required | Default |
|---|---|---|---|
| `bundle_id` | string | yes | — |
| `query` | string | yes | — |
| `timeout` | number | no | `10` (seconds) |

---

## `scroll`

Scroll wheel. Negative `dy` typically scrolls content down.

| Parameter | Type | Required | Default |
|---|---|---|---|
| `bundle_id` | string | no | — |
| `query` | string | no | — |
| `dx` | integer | no | `0` |
| `dy` | integer | no | `0` |

With `bundle_id` + `query`, scrolls over that element's center; otherwise at cursor.

---

## `right_click`

Context click on first element matching `query`.

| Parameter | Type | Required |
|---|---|---|
| `bundle_id` | string | yes |
| `query` | string | yes |

---

## `screenshot`

Capture PNG. Requires Screen Recording permission for window/fullscreen capture.

| Parameter | Type | Required | Default |
|---|---|---|---|
| `bundle_id` | string | no | full screen |
| `return` | string | no | `path` (`path` or `base64`) |

Default returns a temp file path under `/var/folders/...` or `$TMPDIR`.

---

## `menu`

Traverse the menu bar and press an item.

| Parameter | Type | Required |
|---|---|---|
| `bundle_id` | string | yes |
| `path` | string | yes |

`path` uses `/` segments, e.g. `File/New Tab` or localized `ファイル/新規タブ`.

---

## `clip_get` / `clip_set`

Read or replace **general pasteboard** text (global clipboard).

| Tool | Parameters |
|---|---|
| `clip_get` | none |
| `clip_set` | `text` (required) |

**Pattern:** `clip_set` → `key_press` `v` with `modifiers=["cmd"]` to paste.

---

## CLI equivalents

| MCP tool | CLI |
|---|---|
| `list_apps` | `ocu apps` |
| `get_ax_tree` | `ocu tree --bundle-id …` |
| `ax_tree_json` | `ocu tree --bundle-id … --json` |
| `find_element` | `ocu find …` |
| `click_element` | `ocu click …` |
| `activate` | `ocu activate …` |
| `type_text` | `ocu type --text …` |
| `key_press` | `ocu key --key … --mods cmd` |
| `wait_for` | `ocu wait …` |
| `scroll` | `ocu scroll …` |
| `right_click` | `ocu rclick …` |
| `screenshot` | `ocu shot` |
| `menu` | `ocu menu …` |
| `clip_get` / `clip_set` | `ocu clip get` / `ocu clip set` |

Run `ocu --help` for the full list.
