#!/usr/bin/env bash
# Build gate — auto-detects the build system and runs it.
set -euo pipefail

if [ -n "${LG_BUILD_CMD:-}" ]; then
  eval "$LG_BUILD_CMD"
  exit $?
fi

if [ -f Cargo.toml ]; then
  cargo check --quiet 2>&1
  exit $?
fi

if [ -f package.json ] && grep -q '"build"' package.json; then
  npm run build 2>&1
  exit $?
fi

if [ -f Makefile ]; then
  make build 2>&1
  exit $?
fi

# No build system detected — gate passes
exit 0