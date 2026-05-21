#!/usr/bin/env bash
# Build release ocu and install to ~/.local/bin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${INSTALL_DIR:-$HOME/.local/bin}"
BIN="$DEST/ocu"

echo "==> Building OpenComputerUse (release) in $ROOT"
cd "$ROOT"
swift build -c release

SRC="$ROOT/.build/release/ocu"
mkdir -p "$DEST"
cp "$SRC" "$BIN"
chmod +x "$BIN"

echo "==> Installed: $BIN"
"$BIN" --version
echo ""
echo "Add to PATH if needed:"
echo "  export PATH=\"$DEST:\$PATH\""
echo ""
echo "MCP example:"
echo "  claude mcp add opencomputeruse -- $BIN"
