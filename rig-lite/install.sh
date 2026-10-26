#!/usr/bin/env bash
# rig-lite installer — stages the Turbo Flow rules-kit into the current repo.
#
# The curl one-liner is added to the README "Ten-minute install" section once
# the v5.3.0 pin lands; the default version below is always the newest PINNED
# release (a version without a sha in sha_for() is refused).
#
# Fetches a tagged Turbo Flow release tarball, verifies it against a pinned
# sha256, and copies rig-lite/ into the current directory. Installs nothing
# system-wide and touches nothing outside ./rig-lite and one temp dir.
#
# Bash 3.2 compatible (macOS stock bash). Requires curl, tar, and a sha tool
# (sha256sum or shasum). The main() wrapper guards against truncated downloads
# when piped into bash.
set -euo pipefail

sha_for() {
  case "$1" in
    v5.2.0) echo "4d3d22c8477ef519259d3f298ffd26e3fbac6714cee14af5c3385bdf518b28ae" ;;
    *) return 1 ;;
  esac
}

main() {
  version="${TURBO_FLOW_VERSION:-v5.2.0}"
  # TURBO_FLOW_SHA256: explicit pin override (used by the kit's self-test with
  # a stubbed curl; anyone who can set env vars already controls this shell).
  expected="${TURBO_FLOW_SHA256:-$(sha_for "$version")}" || {
    printf 'install.sh: no pinned sha256 for %s — add it to sha_for() first.\n' "$version" >&2
    exit 1
  }

  if [ -e ./rig-lite ]; then
    printf 'install.sh: ./rig-lite already exists here — move it aside before installing.\n' >&2
    exit 1
  fi

  for tool in curl tar; do
    command -v "$tool" >/dev/null 2>&1 || {
      printf 'install.sh: %s is required.\n' "$tool" >&2
      exit 1
    }
  done
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    printf 'install.sh: sha256sum or shasum is required to verify the tarball.\n' >&2
    exit 1
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  url="https://github.com/marcuspat/turbo-flow/archive/refs/tags/${version}.tar.gz"
  printf '==> Fetching Turbo Flow %s ...\n' "$version"
  curl -fsSL "$url" -o "$tmp/turbo-flow.tar.gz"

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/turbo-flow.tar.gz" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "$tmp/turbo-flow.tar.gz" | cut -d' ' -f1)"
  fi
  if [ "$actual" != "$expected" ]; then
    printf 'install.sh: checksum mismatch for %s\n  expected %s\n  actual   %s\n' \
      "$version" "$expected" "$actual" >&2
    exit 1
  fi

  tar -xzf "$tmp/turbo-flow.tar.gz" -C "$tmp"
  srcdir="$tmp/turbo-flow-${version#v}/rig-lite"
  if [ ! -d "$srcdir" ]; then
    printf 'install.sh: rig-lite/ not found inside the %s tarball.\n' "$version" >&2
    exit 1
  fi

  cp -R "$srcdir" ./rig-lite
  printf '==> Staged ./rig-lite from %s — start with rig-lite/constitution.md\n' "$version"
  printf '    The kit installs nothing by design; init-repo.sh wires tf and AGENTS.md.\n'
}

main "$@"
