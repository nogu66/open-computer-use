#!/usr/bin/env bash
# Install ocu to ~/.local/bin from GitHub Release (default: latest).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/github-release.sh
source "$ROOT/scripts/lib/github-release.sh"

REPO="$(ocu_default_repo)"
DEST="${INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${OCU_VERSION:-latest}"
FROM_SOURCE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install the ocu CLI/MCP binary for macOS.

Options:
  --version TAG     Release tag to install (default: latest)
  --from-source     Build from this checkout with SwiftPM instead of downloading
  -h, --help        Show this help

Environment:
  INSTALL_DIR       Install destination (default: ~/.local/bin)
  OCU_VERSION       Same as --version
  OCU_GITHUB_REPO   GitHub repo (default: nogu66/open-computer-use)
  OCU_QUIET=1       Suppress informational output

Examples:
  $(basename "$0")
  $(basename "$0") --version v0.1.0
  INSTALL_DIR=/usr/local/bin $(basename "$0")
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-source)
      FROM_SOURCE=1
      shift
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

install_binary() {
  local bin

  if [[ "$FROM_SOURCE" -eq 1 ]]; then
    bin="$(ocu_install_from_source "$ROOT" "$DEST")"
  else
  if ! bin="$(ocu_install_from_release "$REPO" "$VERSION" "$DEST")"; then
    echo "==> Release download failed; falling back to source build" >&2
    bin="$(ocu_install_from_source "$ROOT" "$DEST")"
  fi
  fi

  if [[ "${OCU_QUIET:-}" != "1" ]]; then
    echo "==> Installed: $bin"
    "$bin" --version
    echo ""
    echo "Add to PATH if needed:"
    echo "  export PATH=\"$DEST:\$PATH\""
    echo ""
    echo "MCP example:"
    echo "  claude mcp add open-computer-use -- $bin"
  fi
}

install_binary
