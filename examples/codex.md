# Codex CLI

## Plugin (recommended)

```bash
codex plugin marketplace add nogu66/open-computer-use
```

Then install **open-computer-use** from the Codex plugin directory.

See [plugin-install.md](plugin-install.md).

## Installed binary

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
codex mcp add open-computer-use $(which ocu)
```

## Dev checkout

```bash
codex mcp add open-computer-use \
  /path/to/open-computer-use/scripts/mcp-server.sh
```

The wrapper resolves `~/.local/bin/ocu` or auto-installs the latest release on first use.

## Verify

```bash
./scripts/smoke-test.sh
```

## Note on Codex Computer Use

OpenAI ships a separate bundled **Codex Computer Use** app (`SkyComputerUseClient`).
`ocu` is an independent open-source implementation with a similar technique (AX +
CGEvent) but not affiliated with OpenAI.
