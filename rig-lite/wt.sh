#!/usr/bin/env bash
# wt.sh — isolated git worktree per agent/task (Law 3: parallel writers
# get isolated worktrees). The documented cure for the multi-agent merge
# tax: parallel writers in separate worktrees, on branches, touching
# disjoint files.
#
# Usage:
#   wt.sh <name> [base]        create .worktrees/<name> + branch <name>, prints path
#   wt.sh --clean <name>       remove worktree + branch
#   wt.sh --list               list this repo's worktrees
set -euo pipefail

MODE=create
if [[ "${1:-}" == "--clean" ]]; then MODE=clean; shift; fi
if [[ "${1:-}" == "--list" ]]; then MODE=list; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,10p' "$0"; exit 0; fi

KIT="$(cd "$(dirname "$0")" && pwd)"   # the rig-lite dir, wherever the kit lives
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "wt.sh: not inside a git repo" >&2; exit 2; }
WTROOT="$ROOT/.worktrees"

case "$MODE" in
  list) git worktree list; exit 0;;
  clean)
    NAME=${1:?usage: wt.sh --clean <name>}
    git worktree remove --force "$WTROOT/$NAME" 2>/dev/null || true
    git branch -D "$NAME" 2>/dev/null || true
    echo "removed: $WTROOT/$NAME (branch $NAME)";;
  create)
    NAME=${1:?usage: wt.sh <name> [base]}
    BASE=${2:-main}
    git show-ref --verify --quiet "refs/heads/$BASE" || BASE=master
    if [[ -e "$WTROOT/$NAME" ]]; then echo "wt.sh: worktree exists: $WTROOT/$NAME" >&2; exit 1; fi
    git worktree add -b "$NAME" "$WTROOT/$NAME" "$BASE" >/dev/null
    echo "$WTROOT/$NAME"
    cat >&2 <<WTEOF
WT · worktree ready: .worktrees/$NAME on branch $NAME (from $BASE)
WT · build there, then when done:
WT ·   $KIT/gate.sh --builder <cli> --base $BASE   # gate the diff (cross-family reviewer)
WT ·   gh pr create                                 # human merges
WT ·   $KIT/wt.sh --clean $NAME                    # tidy up after merge
WTEOF
    ;;
esac
