#!/usr/bin/env bash
# Test gate — auto-detects the test system and runs it.
set -euo pipefail

if [ -n "${LG_TEST_CMD:-}" ]; then
  eval "$LG_TEST_CMD"
  exit $?
fi

if [ -f Cargo.toml ]; then
  cargo test --quiet 2>&1
  exit $?
fi

if [ -f package.json ] && grep -q '"test"' package.json; then
  npm test 2>&1
  exit $?
fi

if [ -f pytest.ini ] || [ -f pyproject.toml ] && grep -q pytest pyproject.toml 2>/dev/null; then
  pytest 2>&1
  exit $?
fi

if [ -f Makefile ] && grep -q 'test' Makefile; then
  make test 2>&1
  exit $?
fi

# No test system detected — gate passes
exit 0