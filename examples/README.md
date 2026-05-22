# MCP client examples

Replace `/path/to/open-computer-use` with your checkout, or install the release binary:

```bash
curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash
```

| File | Client |
|---|---|
| [plugin-install.md](plugin-install.md) | Claude Code / Codex / Cursor plugins |
| [claude-code.md](claude-code.md) | Claude Code (`claude mcp add`) |
| [cursor-mcp.json](cursor-mcp.json) | Cursor (`.cursor/mcp.json` snippet) |
| [codex.md](codex.md) | Codex CLI (`codex mcp add`) |

After adding the server, restart the client and verify with `list_apps` or
`./scripts/smoke-test.sh`.
