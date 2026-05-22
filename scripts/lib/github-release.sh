#!/usr/bin/env bash
# Shared GitHub Release helpers for install.sh and resolve-ocu.sh
set -euo pipefail

ocu_default_repo() {
  printf '%s\n' "${OCU_GITHUB_REPO:-nogu66/open-computer-use}"
}

ocu_normalize_tag() {
  local version="$1"
  if [[ "$version" == "latest" ]]; then
    printf '%s\n' "latest"
    return 0
  fi
  if [[ "$version" == v* ]]; then
    printf '%s\n' "$version"
  else
    printf 'v%s\n' "$version"
  fi
}

ocu_resolve_release_tag() {
  local repo="${1:-$(ocu_default_repo)}"
  local version="${2:-latest}"
  local tag

  tag="$(ocu_normalize_tag "$version")"
  if [[ "$tag" == "latest" ]]; then
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])"
    return 0
  fi

  printf '%s\n' "$tag"
}

ocu_release_tarball_name() {
  local tag="$1"
  printf 'ocu-%s-macos-universal.tar.gz\n' "$tag"
}

ocu_release_download_url() {
  local repo="${1:-$(ocu_default_repo)}"
  local tag="$2"
  local tarball
  tarball="$(ocu_release_tarball_name "$tag")"
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$tag" "$tarball"
}

ocu_install_from_release() {
  local repo="${1:-$(ocu_default_repo)}"
  local version="${2:-latest}"
  local dest="${3:-$HOME/.local/bin}"
  local bin="$dest/ocu"
  local tag tarball url tmpdir extract_dir

  tag="$(ocu_resolve_release_tag "$repo" "$version")"
  tarball="$(ocu_release_tarball_name "$tag")"
  url="$(ocu_release_download_url "$repo" "$tag")"
  tmpdir="$(mktemp -d)"
  extract_dir="$tmpdir/ocu-${tag}-macos-universal"

  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT

  if [[ "${OCU_QUIET:-}" != "1" ]]; then
    echo "==> Downloading ${tag} (${url})" >&2
  fi

  curl -fsSL "$url" -o "$tmpdir/$tarball"

  if curl -fsSL "${url}.sha256" -o "$tmpdir/checksum" 2>/dev/null; then
    (
      cd "$tmpdir"
      expected="$(awk '{print $1}' checksum)"
      actual="$(shasum -a 256 "$tarball" | awk '{print $1}')"
      if [[ "$expected" != "$actual" ]]; then
        echo "error: checksum mismatch for ${tarball}" >&2
        exit 1
      fi
    )
  fi

  tar -xzf "$tmpdir/$tarball" -C "$tmpdir"
  mkdir -p "$dest"
  cp "$extract_dir/ocu" "$bin"
  chmod +x "$bin"
  printf '%s\n' "$bin"
}

ocu_install_from_source() {
  local root="${1:?repo root required}"
  local dest="${2:-$HOME/.local/bin}"
  local bin="$dest/ocu"

  if [[ "${OCU_QUIET:-}" != "1" ]]; then
    echo "==> Building open-computer-use from source in ${root}" >&2
  fi

  if ! command -v swift >/dev/null 2>&1; then
    echo "error: swift not found; install Xcode CLT or download a release binary." >&2
    return 1
  fi

  (
    cd "$root"
    swift build -c release >&2
  )
  mkdir -p "$dest"
  cp "$root/.build/release/ocu" "$bin"
  chmod +x "$bin"
  printf '%s\n' "$bin"
}
