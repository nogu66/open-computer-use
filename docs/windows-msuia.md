# Windows Microsoft UI Automation support

This fork adds a Windows MCP server and CLI path beside the original macOS
Swift implementation.

Windows uses:

- `UIAutomationClient` / `UIAutomationTypes` from Microsoft UI Automation
- Windows PowerShell 5.1
- Win32 foreground-window and mouse helpers for activation and pointer fallback
- Windows Forms clipboard and key sending for text input

Microsoft documents UI Automation as the Windows accessibility framework for
programmatic access to desktop UI elements, and as a way for clients to inspect
and manipulate UI by using element properties and control patterns:

- https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationoverview
- https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-controlpatternsoverview
- https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-howto-find-ui-elements

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (`powershell.exe`)
- Same-user desktop session

UI Automation does not cross every boundary. Elevated apps, different-user
processes, protected system surfaces, and some custom-rendered controls may
return partial trees or reject actions.

## Cursor

The project-level Windows MCP config is `.cursor/mcp.json`:

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
        "${workspaceFolder}/scripts/mcp-server.ps1"
      ]
    }
  }
}
```

Open the checkout in Cursor, then restart Cursor or reload MCP.

The old macOS Cursor config is kept as `.cursor/mcp.macos.json`.

## Codex

For a local checkout, add this MCP server:

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

The Codex plugin manifest points at `.mcp.json`, which now uses the Windows
PowerShell server. The original macOS plugin MCP config is kept as
`.mcp.macos.json`.

## CLI examples

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --app-id chrome --depth 6
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 find --app-id Cursor --query Save
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 shot --out "$env:TEMP\ocu.png"
```

Windows accepts `app_id`, `process_name`, `pid`, `title`, and the existing
`bundle_id` field as a compatibility alias.

## Safety policy

The Windows server blocks risky input before it reaches the desktop:

- recursive or forced Unix deletion such as `rm -rf`
- disk or partition commands such as `dd`, `mkfs`, `fdisk`, and `parted`
- recursive ownership or permission changes such as `chmod -R 777`
- remote script piping such as `curl ... | sh`
- destructive Git cleanup such as `git reset --hard` and `git clean -fd`
- Windows recursive deletion such as `Remove-Item -Recurse`, `del /s`, or `rd /s`
- registry deletion, drive formatting, ownership, and ACL modification commands
- file creation or modification commands such as `Set-Content`, `Out-File`, and `Move-Item`
- in-place Unix edits such as `sed -i` and `perl -pi`
- encoded PowerShell commands
- delete-like UI labels, including `delete`, `remove`, `format`, `wipe`, `reset`, `削除`, and `消去`

`type_text`, `clip_set`, clipboard paste, and pressing Enter after key-by-key
typed input all run through the text safety policy. `click_element`,
`right_click`, `menu`, and `click_ref` run through the UI-label policy.

Override is deliberately two-step:

```powershell
$env:OCU_ALLOW_UNSAFE_INPUT = "1"
```

and the MCP call or CLI command must also pass `allow_unsafe=true` or
`--allow-unsafe`.

## Verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-test-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 safety-check --text "rm -rf /" --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --depth 1 --max-nodes 20
```

The smoke test checks JSON-RPC initialization, tool listing, safe text,
dangerous command detection, and blocking of unsafe `type_text`.

## Optional Swift verification on Windows

The Windows desktop server is PowerShell-based, but `OCUCore` can be built and
tested with the official Swift toolchain for Windows.

Install:

```powershell
winget install --id Swift.Toolchain -e --source winget --silent --accept-package-agreements --accept-source-agreements
```

Run from a Visual Studio x64 developer environment, or call `vcvars64.bat`:

```cmd
cmd.exe /v:on /d /c "\"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat\" && set \"SWIFT_ROOT=%LOCALAPPDATA%\Programs\Swift\" && set \"SDKROOT=!SWIFT_ROOT!\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk\" && set \"PATH=!SWIFT_ROOT!\Toolchains\6.3.2+Asserts\usr\bin;!SWIFT_ROOT!\Runtimes\6.3.2\usr\bin;!PATH!\" && swift test"
```

`Package.swift` intentionally exposes only `OCUCore` on Windows. The Swift
`ocu` executable remains macOS-only because it imports `AppKit` and
`ApplicationServices`.
