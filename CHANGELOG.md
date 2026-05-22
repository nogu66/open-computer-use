# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Windows MCP/CLI path using PowerShell and Microsoft UI Automation.
- Guardrails for destructive typed commands, unsafe paste, file modification
  commands, recursive deletion, and delete-like UI labels on Windows.
- Windows MCP smoke test script and GitHub Actions Windows smoke job.

### Changed

- `Package.swift` now exposes the macOS `ocu` executable target only on macOS so
  `OCUCore` can build and test on Windows.

## [0.1.0] - 2026-05-22

### Added

- `ocu` executable: MCP stdio server and CLI in one binary.
- MCP tools: `list_apps`, `get_ax_tree`, `ax_tree_json`, `find_element`,
  `click_element`, `click_ref`, `activate`, `type_text`, `key_press`,
  `wait_for`, `scroll`, `right_click`, `screenshot`, `menu`, `clip_get`,
  `clip_set`.
- CLI subcommands mirroring common tool operations (`apps`, `tree`, `click`, …).
- `OCUCore` library: version metadata, CLI argument parsing, JSON-RPC helpers.
- XCTest suite for `OCUCore` (runs in CI without Accessibility grants).
- GitHub Actions: CI on macOS 14/15, release workflow for universal binaries.
- Claude Code, Codex, and Cursor plugin manifests (`.claude-plugin/`, `.codex-plugin/`, `.agents/plugins/`, `.cursor/`).
- Bundled agent skill and MCP wrapper scripts (`skills/`, `scripts/mcp-server.sh`).
- `scripts/lib/github-release.sh` and release-first `scripts/install.sh` (default: latest GitHub Release).
- Documentation, examples, and install/smoke-test scripts.

### Changed

- User-facing docs and examples use the `open-computer-use` name and GitHub URL consistently.
- MCP wrappers auto-install the latest release to `~/.local/bin/ocu` when the binary is missing.
- Release tarballs include `install.sh`.

[Unreleased]: https://github.com/nogu66/open-computer-use/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nogu66/open-computer-use/releases/tag/v0.1.0
