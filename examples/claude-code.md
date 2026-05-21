# Claude Code

## Installed binary

```bash
# after ./scripts/install.sh
claude mcp add opencomputeruse -- $(which ocu)
```

## Dev checkout (SwiftPM)

```bash
claude mcp add opencomputeruse -- \
  swift run -c release --package-path /path/to/OpenComputerUse ocu
```

Restart Claude Code. Tools appear as `mcp__opencomputeruse__<tool_name>`.

## Verify

Ask the agent to call `list_apps`, or run locally:

```bash
./scripts/smoke-test.sh
```

## Permissions

Grant **Accessibility** to Claude Code in System Settings. See
[../docs/permissions.md](../docs/permissions.md).
