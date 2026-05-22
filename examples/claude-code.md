# Claude Code

## Plugin (recommended)

```text
/plugin marketplace add nogu66/open-computer-use
/plugin install open-computer-use@open-computer-use
/reload-plugins
```

See [plugin-install.md](plugin-install.md).

## Installed binary

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
claude mcp add open-computer-use -- $(which ocu)
```

## Dev checkout (wrapper auto-installs latest release)

```bash
claude mcp add open-computer-use -- \
  /path/to/open-computer-use/scripts/mcp-server.sh
```

Restart Claude Code. Tools appear as `mcp__open-computer-use__<tool_name>`.

## Verify

Ask the agent to call `list_apps`, or run locally:

```bash
./scripts/smoke-test.sh
```

## Permissions

Grant **Accessibility** to Claude Code in System Settings. See
[../docs/permissions.md](../docs/permissions.md).
