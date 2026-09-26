#!/usr/bin/env bash
# init-repo.sh — onboard a repo onto the rig-lite kit. Run ONCE per repo, then forget it.
#
# What it does:
#   1. creates a thin AGENTS.md (constitution pointer + project cheat-sheet;
#      kit outside this repo → the constitution is copied in, so every clone resolves it)
#   2. symlinks CLAUDE.md → AGENTS.md (one source, no drift; Codex reads AGENTS.md natively)
#
# Usage:  from anywhere inside the repo (root, subdir, or a wt.sh worktree):
#         path/to/rig-lite/init-repo.sh ["Project name"]
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,10p' "$0"; exit 0; fi

# rev-parse, not [[ -d .git ]]: in a worktree .git is a FILE, and onboarding
# from inside a wt.sh worktree is this kit's own workflow
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "init-repo: run me from inside a git repo (or worktree)" >&2; exit 2; }
NAME=${1:-$(basename "$ROOT")}
KIT="$(cd "$(dirname "$0")" && pwd)"   # the rig-lite dir, wherever the kit lives
[[ -f "$KIT/constitution.md" ]] || { echo "init-repo: kit not found at $KIT (constitution.md missing)" >&2; exit 2; }
cd "$ROOT"   # anchor every write + relative pointer at the repo root, not $PWD

# Constitution pointer must survive the commit and resolve in EVERY clone:
# kit inside this repo → repo-relative path; kit outside → copy the
# constitution in (one file, self-contained repo, no dead absolute paths).
# Whatever gets created is collected so the closing message can tell the
# operator exactly what to git add — an uncommitted copy would dead-point
# every clone but this one.
CREATED=""
if [[ "$KIT" == "$ROOT"/* ]]; then
  POINTER="${KIT#"$ROOT"/}/constitution.md"
else
  POINTER="rig-constitution.md"
  if [[ ! -f "$ROOT/$POINTER" ]]; then
    cp "$KIT/constitution.md" "$ROOT/$POINTER"
    CREATED+=" $POINTER"
    echo "init-repo: kit lives outside this repo — copied the constitution to $POINTER"
  else
    echo "init-repo: $POINTER already present — left untouched (it's a template; your edits are yours)"
  fi
fi

# 1. thin AGENTS.md — only if absent (never clobber an existing one).
#    printf %s + a QUOTED heredoc: the project name is argv, and an unquoted
#    heredoc would run command substitution inside it ($(rm -rf ~) etc.)
if [[ ! -f AGENTS.md ]]; then
  {
    printf '# %s — agent instructions\n\n' "$NAME"
    printf 'Read and follow the constitution: %s (gate every PR, agents never merge, state on disk).\n\n' "$POINTER"
    cat <<'EOF'
## Project cheat-sheet (fill in, one line each — agents read this every session)
- Stack:
- Run tests:
- Run locally:
- Deploy:
- Gotchas:
EOF
  } > AGENTS.md
  CREATED+=" AGENTS.md"
  echo "init-repo: wrote AGENTS.md"
else
  echo "init-repo: AGENTS.md already present — left untouched"
fi

# 2. CLAUDE.md symlink (Claude reads it; never overwrite a real file)
if [[ ! -e CLAUDE.md ]]; then
  ln -s AGENTS.md CLAUDE.md
  CREATED+=" CLAUDE.md"
  echo "init-repo: CLAUDE.md → AGENTS.md"
elif [[ -L CLAUDE.md ]]; then
  echo "init-repo: CLAUDE.md symlink already present"
else
  echo "init-repo: real CLAUDE.md exists — left untouched"
fi

echo
echo "Done. From now on: build on branches, gate with:"
echo "  $KIT/gate.sh --builder <cli> --base main   # reviewer ≠ builder's family"
if [[ -n "$CREATED" ]]; then
  echo "Commit the onboarding files (uncommitted, the constitution pointer dead-ends in every other clone):"
  echo "  git add$CREATED"
fi
echo "Fill the cheat-sheet lines in AGENTS.md whenever convenient — better cheat-sheet, better agents."
