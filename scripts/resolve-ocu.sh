#!/usr/bin/env bash
# Resolve the ocu binary for MCP/CLI wrappers.
set -euo pipefail

resolve_ocu() {
  local root="${1:?plugin root required}"
  local candidate

  if command -v ocu >/dev/null 2>&1; then
    command -v ocu
    return 0
  fi

  if [[ -n "${OCU_BIN:-}" && -x "${OCU_BIN}" ]]; then
    printf '%s\n' "${OCU_BIN}"
    return 0
  fi

  candidate="${HOME}/.local/bin/ocu"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  local release_bin="${root}/.build/release/ocu"
  if [[ -x "$release_bin" ]]; then
    printf '%s\n' "$release_bin"
    return 0
  fi

  if [[ "${OCU_SKIP_AUTO_INSTALL:-}" != "1" && -x "${root}/scripts/install.sh" ]]; then
    OCU_QUIET=1 "${root}/scripts/install.sh" || true
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if [[ "${OCU_FROM_SOURCE:-}" == "1" ]] && command -v swift >/dev/null 2>&1; then
    # shellcheck source=lib/github-release.sh
    source "${root}/scripts/lib/github-release.sh"
    ocu_install_from_source "$root" "${INSTALL_DIR:-$HOME/.local/bin}" >/dev/null
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  echo "error: ocu not found. Run: curl -fsSL https://raw.githubusercontent.com/nogu66/open-computer-use/main/scripts/install.sh | bash" >&2
  return 1
}
