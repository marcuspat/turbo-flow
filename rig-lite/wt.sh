#!/usr/bin/env bash
# wt.sh — isolated git worktree per agent/task (Law 3: parallel writers
# get isolated worktrees). The documented cure for the multi-agent merge
# tax: parallel writers in separate worktrees, on branches, touching
# disjoint files.
#
# Usage:
#   wt.sh <name> [base]        create .worktrees/<name> + branch <name>, prints path
#                              (name: letters/digits/dot/underscore/dash only)
#   wt.sh --clean <name>       remove worktree + branch (fails loudly on refusal;
#                              "nothing to clean" is exit 0)
#   wt.sh --list               list this repo's worktrees
set -euo pipefail

MODE=create
if [[ "${1:-}" == "--clean" ]]; then MODE=clean; shift; fi
if [[ "${1:-}" == "--list" ]]; then MODE=list; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,12p' "$0"; exit 0; fi

# a worktree name becomes BOTH a path under this repo and a git ref —
# strict charset only (no /, no .., no leading dash/flag shapes)
RE_NAME='^[A-Za-z0-9][A-Za-z0-9._-]*$'
valid_name() { [[ "$1" =~ $RE_NAME ]]; }

KIT="$(cd "$(dirname "$0")" && pwd)"   # the rig-lite dir, wherever the kit lives
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "wt.sh: not inside a git repo" >&2; exit 2; }
WTROOT="$ROOT/.worktrees"

case "$MODE" in
  list) git worktree list; exit 0;;
  clean)
    NAME=${1:?usage: wt.sh --clean <name>}
    valid_name "$NAME" || { echo "wt.sh: invalid name '$NAME' (allowed: letters, digits, dot, underscore, dash)" >&2; exit 2; }
    git worktree prune
    RC=0; FOUND=0
    if [[ -e "$WTROOT/$NAME" ]] || git worktree list --porcelain | grep -q "^worktree $WTROOT/$NAME$"; then
      FOUND=1
      git worktree remove --force "$WTROOT/$NAME" || { echo "wt.sh: failed to remove worktree $NAME" >&2; RC=1; }
    fi
    if git show-ref --verify --quiet "refs/heads/$NAME"; then
      FOUND=1
      git branch -D "$NAME" || { echo "wt.sh: failed to delete branch $NAME (checked out elsewhere?)" >&2; RC=1; }
    fi
    if [[ $RC -eq 0 ]]; then
      if [[ $FOUND -eq 1 ]]; then echo "cleaned: $WTROOT/$NAME (branch $NAME)"
      else echo "wt.sh: nothing to clean for $NAME"; fi
    fi
    exit $RC;;
  create)
    NAME=${1:?usage: wt.sh <name> [base]}
    valid_name "$NAME" || { echo "wt.sh: invalid name '$NAME' (allowed: letters, digits, dot, underscore, dash)" >&2; exit 2; }
    BASE=${2:-main}
    if [[ $# -ge 2 ]]; then
      # an explicit base must exist as-is — no silent retargeting (and no
      # empty-string base silently becoming main)
      [[ -n "$2" ]] || { echo "wt.sh: base branch name is empty" >&2; exit 2; }
      git show-ref --verify --quiet "refs/heads/$BASE" || { echo "wt.sh: base branch '$BASE' not found" >&2; exit 2; }
    else
      # default base only: main, falling back to master on old repos —
      # and the fallback itself must exist or we refuse (empty repo)
      git show-ref --verify --quiet "refs/heads/main" || BASE=master
      git show-ref --verify --quiet "refs/heads/$BASE" || { echo "wt.sh: neither main nor master exists (empty repo? commit first)" >&2; exit 2; }
    fi
    if [[ -e "$WTROOT/$NAME" ]]; then echo "wt.sh: worktree exists: $WTROOT/$NAME" >&2; exit 1; fi
    if git show-ref --verify --quiet "refs/heads/$NAME"; then
      echo "wt.sh: branch '$NAME' already exists (partial --clean?) — delete it or pick another name" >&2; exit 1
    fi
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
