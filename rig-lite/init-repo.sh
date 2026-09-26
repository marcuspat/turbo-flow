#!/usr/bin/env bash
# init-repo.sh — onboard a repo onto the rig-lite kit. Run ONCE per repo, then forget it.
#
# What it does:
#   1. creates a thin AGENTS.md (constitution pointer + project cheat-sheet)
#   2. symlinks CLAUDE.md → AGENTS.md (one source, no drift; Codex reads AGENTS.md natively)
#
# Usage:  cd <repo>  &&  path/to/rig-lite/init-repo.sh ["Project name"]
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,8p' "$0"; exit 0; fi

[[ -d .git ]] || { echo "init-repo: run me from inside a git repo" >&2; exit 2; }
NAME=${1:-$(basename "$PWD")}
KIT="$(cd "$(dirname "$0")" && pwd)"   # the rig-lite dir, wherever the kit lives
[[ -f "$KIT/constitution.md" ]] || { echo "init-repo: kit not found at $KIT (constitution.md missing)" >&2; exit 2; }

# 1. thin AGENTS.md — only if absent (never clobber an existing one)
if [[ ! -f AGENTS.md ]]; then
  cat > AGENTS.md <<EOF
# $NAME — agent instructions

Read and follow the constitution: $KIT/constitution.md (gate every PR, agents never merge, state on disk).

## Project cheat-sheet (fill in, one line each — agents read this every session)
- Stack:
- Run tests:
- Run locally:
- Deploy:
- Gotchas:
EOF
  echo "init-repo: wrote AGENTS.md"
else
  echo "init-repo: AGENTS.md already present — left untouched"
fi

# 2. CLAUDE.md symlink (Claude reads it; never overwrite a real file)
if [[ ! -e CLAUDE.md ]]; then
  ln -s AGENTS.md CLAUDE.md
  echo "init-repo: CLAUDE.md → AGENTS.md"
elif [[ -L CLAUDE.md ]]; then
  echo "init-repo: CLAUDE.md symlink already present"
else
  echo "init-repo: real CLAUDE.md exists — left untouched"
fi

echo
echo "Done. From now on: build on branches, gate with:"
echo "  $KIT/gate.sh --builder <cli> --base main   # reviewer ≠ builder's family"
echo "Fill the cheat-sheet lines in AGENTS.md whenever convenient — better cheat-sheet, better agents."
