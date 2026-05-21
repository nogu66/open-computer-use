# Contributing to OpenComputerUse

Thanks for your interest in improving `ocu`. This document covers the
basics; the bar for first-time contributors is low — typo fixes and small
quality-of-life patches are very welcome.

## Code of conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md).
By participating you agree to abide by it.

## Ground rules

- `ocu` is **macOS only**. It depends on `ApplicationServices`, `AppKit` and
  `CoreGraphics`. Cross-platform PRs are out of scope.
- Keep the binary small and dependency-light. No external Swift packages
  unless there's a strong reason.
- Tests should be runnable in CI without any UI permission grants. Put
  permission-requiring logic in `Sources/ocu/main.swift`; put pure helpers
  in `Sources/OCUCore/` so they can be unit tested.

## Development setup

Requirements:

- macOS 13+ (Ventura or later)
- Swift 5.9+ (Xcode 15+)

```bash
git clone https://github.com/nogu66/OpenComputerUse.git
cd OpenComputerUse
swift build
swift test
.build/debug/ocu --help
```

To exercise the MCP loop end-to-end:

```bash
swift build -c release
./scripts/smoke-test.sh        # sends initialize → tools/list → list_apps
```

You will need to grant Accessibility permission to whichever process you
run `ocu` under (Terminal / Ghostty / your editor). The first request
that touches AX will prompt; allow it once and rebuild does not invalidate
the grant unless the binary is renamed.

## Project layout

```
.
├── Package.swift                  swift-tools-version: 5.9
├── Sources/
│   ├── OCUCore/                   pure, testable helpers (no AppKit/AX deps)
│   └── ocu/                       executable; everything that touches macOS APIs
├── Tests/OCUCoreTests/            XCTest, runs in CI without UI permissions
├── docs/                          permissions / architecture / tool reference
├── examples/                      MCP client configs (Claude Code, Codex)
├── scripts/                       install / smoke-test
└── .github/                       CI, issue & PR templates
```

## Pull request workflow

1. Open or pick up an issue first. For non-trivial features, describe your
   plan before sending the code.
2. Branch off `main`, keep PRs focused (one logical change per PR).
3. Run `swift build && swift test` locally before pushing.
4. Update `CHANGELOG.md` under the `## [Unreleased]` heading.
5. Update `README.md` (and `README.ja.md` if you can) when the change is
   user-visible.

## Adding a new MCP tool

1. Implement the handler in `Sources/ocu/main.swift` as a `t_<name>` function
   returning `[String: Any]` via `toolResult` / `toolError`.
2. Add it to the `toolsList` array with a clear `description` and a
   minimal `inputSchema` — descriptions are read by the LLM, so be concrete
   about preconditions ("call `activate` first", etc.).
3. Wire it into the `handleTool` switch.
4. Add a CLI subcommand in `cliMain` if it's useful from the shell.
5. Document it in `docs/tools.md` and add an example to `README.md`.

## Coding style

- Format with `swift-format` if you have it installed (`swift-format format -i -r Sources Tests`).
- 4-space indentation, no tabs.
- Prefer small free functions over heavyweight classes — this codebase is
  intentionally a single-file executable for hackability.
- Log via the `log(_:)` helper (writes to stderr). **Never** write to stdout
  outside of JSON-RPC responses — that corrupts the MCP framing.

## Releasing (maintainers)

1. Bump `OpenComputerUse.version` in `Sources/OCUCore/Version.swift`.
2. Move `## [Unreleased]` entries into a new dated section in `CHANGELOG.md`.
3. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. The `release.yml` workflow builds a universal binary and attaches it
   to the GitHub release.
