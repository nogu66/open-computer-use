#!/usr/bin/env bash
# MCP stdio entrypoint for plugin installs (Claude Code, Codex, Cursor).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=resolve-ocu.sh
source "${ROOT}/scripts/resolve-ocu.sh"

OCU="$(resolve_ocu "${ROOT}")"
exec "${OCU}"
