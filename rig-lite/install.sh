#!/usr/bin/env bash
# rig-lite installer — stages the Turbo Flow rules-kit into the current repo.
#
# One-liner (documented in the README "Ten-minute install" section):
#   curl -fsSL https://github.com/marcuspat/turbo-flow/raw/main/rig-lite/install.sh | bash
#
# Fetches a tagged Turbo Flow release tarball, verifies it against a pinned
# sha256, and copies rig-lite/ into the current directory. Installs nothing
# system-wide and touches nothing outside ./rig-lite and one temp dir.
#
# Bash 3.2 compatible (macOS stock bash). Requires curl and tar.
set -euo pipefail

sha_for() {
  case "$1" in
    v5.2.0) echo "4d3d22c8477ef519259d3f298ffd26e3fbac6714cee14af5c3385bdf518b28ae" ;;
    *) return 1 ;;
  esac
}

version="${TURBO_FLOW_VERSION:-v5.3.0}"
expected="$(sha_for "$version")" || {
  printf 'install.sh: no pinned sha256 for %s yet.\n' "$version" >&2
  printf '  If the release tag is already cut, add its tarball sha256 to sha_for().\n' >&2
  printf '  To stage the previous kit now: TURBO_FLOW_VERSION=v5.2.0 <this script>\n' >&2
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
