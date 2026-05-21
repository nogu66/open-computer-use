# Codex CLI

## Installed binary

```bash
codex mcp add opencomputeruse $(which ocu)
```

## Dev checkout

```bash
codex mcp add opencomputeruse \
  swift /path/to/OpenComputerUse/.build/release/ocu
```

Some Codex versions expect the command as a single executable path; prefer the
release binary from `swift build -c release` over `swift run` for faster startup.

## Verify

```bash
./scripts/smoke-test.sh
```

## Note on Codex Computer Use

OpenAI ships a separate bundled **Codex Computer Use** app (`SkyComputerUseClient`).
`ocu` is an independent open-source implementation with a similar technique (AX +
CGEvent) but not affiliated with OpenAI.
