#!/usr/bin/env bash
# bootstrap.sh — Initialize brain-vault and brain-intake repos.
set -euo pipefail

: "${BRAIN_VAULT:=$HOME/brain-vault}"
: "${BRAIN_INTAKE:=$HOME/brain-intake}"
TB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Initializing vault at $BRAIN_VAULT"
if [ ! -d "$BRAIN_VAULT/.git" ]; then
  mkdir -p "$BRAIN_VAULT"
  git init "$BRAIN_VAULT"
fi

# Create vault directory structure
for d in profile areas people projects topics daily; do
  mkdir -p "$BRAIN_VAULT/$d"
done

# Seed INDEX.md if absent
if [ ! -f "$BRAIN_VAULT/INDEX.md" ]; then
  cat > "$BRAIN_VAULT/INDEX.md" << 'VAULTINDEX'
---
name: INDEX
description: always-loaded vault index — hard-capped at 200 lines / 25 KB
sources: [seed]
sensitivity: private
---
- [stated] This is the Turbo Brain vault index — loaded first by any reader
- [stated] Use brain_search for specific queries, brain_read for full files
- [stated] Facts tagged [stated] are first-person; [ingested] from adapters; [derived] from waves
VAULTINDEX
  echo "    seeded INDEX.md"
fi

# Seed CLIENTS.deny if absent
if [ ! -f "$BRAIN_VAULT/CLIENTS.deny" ]; then
  cat > "$BRAIN_VAULT/CLIENTS.deny" << 'DENY'
# CLIENTS.DENY — one term per line, # comments.
# Domains containing '.' are matched as bare substrings.
# All other terms are matched on word boundaries (case-insensitive).
# Used by deny_scan.py (D8 L1).
#
# IMPORTANT: an empty deny-list causes vault commits to fail (vacuous-pass protection).
# Add at least one real client name before using the vault.
#
# Example:
# acme-corp
# bigco.com
DENY
  echo "    seeded CLIENTS.deny (populate with real client names!)"
fi

# Seed .turbo-brain.toml if absent
if [ ! -f "$BRAIN_VAULT/.turbo-brain.toml" ]; then
  cat > "$BRAIN_VAULT/.turbo-brain.toml" << 'TOML'
# Turbo Brain configuration
tool_version = "0.2.0"
no_net_loss_pct = 5.0
additions_cap_pct = 50.0
TOML
  echo "    seeded .turbo-brain.toml"
fi

# Initial commit if repo is empty
if [ -d "$BRAIN_VAULT/.git" ] && cd "$BRAIN_VAULT" && [ -z "$(git log --oneline 2>/dev/null)" ]; then
  git add -A
  git commit -m "bootstrap: initialize vault structure"
  echo "    initial vault commit"
fi

echo ""
echo "==> Initializing intake at $BRAIN_INTAKE"
if [ ! -d "$BRAIN_INTAKE/.git" ]; then
  mkdir -p "$BRAIN_INTAKE"
  git init "$BRAIN_INTAKE"
fi

for d in inbox ledger quarantine; do
  mkdir -p "$BRAIN_INTAKE/$d"
done

# Initial commit if repo is empty
if [ -d "$BRAIN_INTAKE/.git" ] && cd "$BRAIN_INTAKE" && [ -z "$(git log --oneline 2>/dev/null)" ]; then
  git add -A
  git commit -m "bootstrap: initialize intake structure"
  echo "    initial intake commit"
fi

echo ""
echo "==> Done. Next steps:"
echo "    export TB_ROOT=$TB_ROOT"
echo "    export PATH=\"\$TB_ROOT/bin:\$PATH\""
echo "    export BRAIN_VAULT=$BRAIN_VAULT"
echo "    export BRAIN_INTAKE=$BRAIN_INTAKE"
echo "    turbo-brain doctor"
echo "    turbo-brain selftest"
echo ""
echo "  Then populate CLIENTS.deny and run:"
echo "    turbo-brain install-hooks"
