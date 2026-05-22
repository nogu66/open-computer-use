#!/usr/bin/env bash
# CLI wrapper for skills and docs (same binary resolution as mcp-server.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=resolve-ocu.sh
source "${ROOT}/scripts/resolve-ocu.sh"

OCU="$(resolve_ocu "${ROOT}")"
exec "${OCU}" "$@"
