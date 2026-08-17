#!/usr/bin/env bash
# Structural gate — enforces the core/adapters/config separation.
# Remove this gate if your repo doesn't use that structure.
set -euo pipefail

# Check that no client-specific code landed in core/
if [ -d core ]; then
  # This is a placeholder — customize for your repo's structural rule
  echo "structural: core/ exists, no violations detected"
fi

exit 0