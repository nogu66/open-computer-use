# Windows MS UI Automation guardrails implementation log

**Date**: 2026-05-22
**Agent**: Codex
**Workspace**: `C:\Users\downl\Desktop\open-computer-use`

## Overview

Forked `nogu66/open-computer-use` to `zapabob/open-computer-use` and added a
Windows MCP/CLI path that uses Microsoft UI Automation through Windows
PowerShell 5.1. The existing macOS Swift path remains available through the
macOS MCP config files.

## Background / requirements

- Enable Cursor and Codex to operate this Windows PC through the fork.
- Use Microsoft UI Automation for Windows, because the upstream project was
  macOS-focused.
- Add guardrails for dangerous Unix commands, Windows deletion, file
  modification, and delete-like UI actions.
- Keep implementation evidence and verification results in `_docs`.

## Assumptions / decisions

- Windows desktop automation is a PowerShell path instead of Swift/WinSDK
  because PowerShell 5.1 already exposes `UIAutomationClient` without a
  compiled Windows bridge. Swift is installed for package build/test
  verification.
- Cursor and Codex default configs now launch the Windows server.
- macOS configs are retained as `.mcp.macos.json` and `.cursor/mcp.macos.json`.
- Unsafe override requires both an operator environment variable and an explicit
  tool/CLI flag.

## Changed files

- `scripts/ocu-windows.ps1`
- `scripts/mcp-server.ps1`
- `scripts/mcp-server.cmd`
- `scripts/smoke-test-windows.ps1`
- `Package.swift`
- `.github/workflows/ci.yml`
- `.github/pull_request_template.md`
- `CHANGELOG.md`
- `.mcp.json`
- `.mcp.macos.json`
- `.cursor/mcp.json`
- `.cursor/mcp.macos.json`
- `.codex-plugin/plugin.json`
- `.claude-plugin/plugin.json`
- `README.md`
- `docs/windows-msuia.md`
- `docs/architecture.md`
- `docs/tools.md`
- `docs/permissions.md`
- `examples/codex.md`
- `examples/codex-windows.md`
- `examples/cursor-mcp.json`
- `examples/cursor-mcp.windows.json`
- `examples/plugin-install.md`
- `skills/open-computer-use/SKILL.md`
- `.cursor/skills/open-computer-use/SKILL.md`

## Implementation details

- Added UIA tree traversal, JSON tree export, element search, InvokePattern
  click, pointer fallback, activation, screenshot, clipboard, typing, key press,
  scroll, and menu helpers for Windows.
- Added safety checks for destructive shell text, recursive deletion, disk
  commands, file modification commands, destructive Git cleanup, remote script
  piping, encoded PowerShell, and delete-like UI labels.
- Added stateful key buffering so key-by-key command entry is checked when
  Enter is pressed.
- Added clipboard paste checks so externally or internally staged dangerous
  commands are not pasted by shortcut.
- Added MCP smoke test coverage for initialization, tool listing, allowed text,
  blocked destructive text, and blocked unsafe typing.
- Updated `Package.swift` so the macOS Swift executable target is only defined
  on macOS; Windows Swift now builds/tests the platform-free `OCUCore` library.
- Added a Windows GitHub Actions smoke job for JSON config validation and MCP
  smoke coverage.

## Commands run

```text
gh repo fork nogu66/open-computer-use --clone --fork-name open-computer-use --default-branch-only
git switch -c feature/windows-msuia-guardrails
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 safety-check --text "rm -rf /" --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 safety-check --text "echo hello" --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-test-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --depth 1 --max-nodes 20
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 shot --out $env:TEMP\ocu-smoke.png
winget install --id Swift.Toolchain -e --source winget --silent --accept-package-agreements --accept-source-agreements
cmd.exe /v:on /d /c '"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" && set "SWIFT_ROOT=%LOCALAPPDATA%\Programs\Swift" && set "SDKROOT=!SWIFT_ROOT!\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk" && set "PATH=!SWIFT_ROOT!\Toolchains\6.3.2+Asserts\usr\bin;!SWIFT_ROOT!\Runtimes\6.3.2\usr\bin;!PATH!" && swift build -v'
cmd.exe /v:on /d /c '"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" && set "SWIFT_ROOT=%LOCALAPPDATA%\Programs\Swift" && set "SDKROOT=!SWIFT_ROOT!\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk" && set "PATH=!SWIFT_ROOT!\Toolchains\6.3.2+Asserts\usr\bin;!SWIFT_ROOT!\Runtimes\6.3.2\usr\bin;!PATH!" && swift test -v'
```

## Test / verification results

- `safety-check --text "rm -rf /"` returned `allowed=false` with
  `rule=unix-rm-recursive`.
- `safety-check --text "echo hello"` returned `allowed=true`.
- `scripts\smoke-test-windows.ps1` passed.
- `apps` listed running GUI processes and exited `0`.
- `tree --depth 1 --max-nodes 20` returned a UI Automation tree for the current
  foreground window.
- `shot --out $env:TEMP\ocu-smoke.png` produced a PNG screenshot.
- Swift 6.3.2 installed successfully with `winget ... --silent`.
- `swift build -v` passed on Windows after setting Visual Studio x64 developer
  environment, `SDKROOT`, and Swift runtime/toolchain PATH.
- `swift test -v` passed on Windows: 17 XCTest tests, 0 failures.

## Residual risks

- macOS Swift build/test still requires macOS CI because the `ocu` executable
  imports `AppKit` and `ApplicationServices`.
- UI Automation cannot reliably operate elevated windows from a non-elevated
  agent, other-user sessions, protected system surfaces, or controls that do not
  expose useful UIA metadata.
- The guardrail is a defensive local policy, not a complete sandbox. It reduces
  accidental or prompt-injected destructive desktop input but cannot police
  every possible GUI path.

## Recommended next actions

- Install or use a Swift toolchain runner to verify the unchanged macOS Swift
  package.
- Watch the GitHub Actions Windows smoke job after the PR branch is pushed.
- If plugin manifests later gain OS selection, split the Windows and macOS MCP
  configs instead of keeping a single default.
