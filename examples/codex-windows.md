# Codex on Windows

Use the Windows PowerShell MCP server from this checkout:

```json
{
  "mcpServers": {
    "open-computer-use": {
      "command": "powershell.exe",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "C:/Users/downl/Desktop/open-computer-use/scripts/mcp-server.ps1"
      ]
    }
  }
}
```

Verify locally:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-test-windows.ps1
```

Windows uses Microsoft UI Automation. Prefer `list_apps`, `activate`,
`get_ax_tree`, and then `click_element` or `click_ref`.

Dangerous typed commands and delete-like UI labels are blocked by default.
Override requires both `OCU_ALLOW_UNSAFE_INPUT=1` and `allow_unsafe=true`.
