# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Nothing yet.

## [0.1.0] - 2026-05-21

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
- Documentation, examples, and install/smoke-test scripts.

[Unreleased]: https://github.com/nogu66/OpenComputerUse/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nogu66/OpenComputerUse/releases/tag/v0.1.0
