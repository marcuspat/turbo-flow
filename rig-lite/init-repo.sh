#!/usr/bin/env bash
# init-repo.sh — onboard a repo onto the rig-lite kit. Run ONCE per repo, then forget it.
#
# What it does:
#   1. creates a thin AGENTS.md (constitution pointer + project cheat-sheet;
#      kit outside this repo → the constitution is copied in, so every clone resolves it)
#   2. symlinks CLAUDE.md → AGENTS.md (one source, no drift; Codex reads AGENTS.md natively)
#   3. installs the deletion-guard pre-commit hook into the repo's git dir
#      (worktree-aware; skipped if a hook already exists)
#
# Usage:  from anywhere inside the repo (root, subdir, or a wt.sh worktree):
#         path/to/rig-lite/init-repo.sh ["Project name"]
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,12p' "$0"; exit 0; fi

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

# 3. deletion-guard pre-commit hook — into the REPO'S OWN hooks dir (the
#    common git dir, so worktrees share it), copy only if absent.
#    Deliberately NOT `git rev-parse --git-path hooks`: that honors a global
#    core.hooksPath and would install into a foreign hooks dir — so we resolve
#    the common dir ourselves and WARN when core.hooksPath redirects hooks.
#    cwd IS the repo root here (cd'd above), so a relative common-dir anchors
#    to it via pwd — immune to subdir invocation and toplevel/cwd skew.
COMMON="$(git rev-parse --git-common-dir)"
[[ "$COMMON" == /* ]] || COMMON="$(pwd -P)/$COMMON"
HOOKS_DIR="$COMMON/hooks"
if [[ -f "$KIT/hooks/pre-commit" && ! -e "$HOOKS_DIR/pre-commit" ]]; then
  mkdir -p "$HOOKS_DIR"
  # no half-installs: a copied-but-unexecutable hook would be silently inert
  # (and the ! -e guard would refuse to repair it on rerun)
  if cp "$KIT/hooks/pre-commit" "$HOOKS_DIR/pre-commit" && chmod +x "$HOOKS_DIR/pre-commit"; then
    echo "init-repo: deletion-guard pre-commit installed"
  else
    rm -f "$HOOKS_DIR/pre-commit"
    echo "init-repo: hook install failed — removed the partial copy (nothing silently inert left behind)" >&2
  fi
elif [[ -e "$HOOKS_DIR/pre-commit" ]]; then
  echo "init-repo: a pre-commit hook already exists — left untouched"
fi
if [[ -n "$(git config core.hooksPath 2>/dev/null)" ]]; then
  echo "init-repo: NOTE — core.hooksPath is configured on this repo/machine: repo-local hooks may not run. Point it at (or include) $HOOKS_DIR if you want the deletion guard active." >&2
fi

echo
echo "Done. From now on, use tf (one command for everything):"
echo "  tf gate --builder <cli>   # gate the current branch (builder names itself)"
echo "  tf status        # everything at a glance"
echo "  tf test          # self-test"
if [[ -n "$CREATED" ]]; then
  echo "Commit the onboarding files (uncommitted, the constitution pointer dead-ends in every other clone):"
  echo "  git add$CREATED"
fi
echo "Fill the cheat-sheet lines in AGENTS.md whenever convenient — better cheat-sheet, better agents."

# 4. install the tf CLI to ~/.local/bin as a WRAPPER pointing at the kit
#    (a copy would lose the kit reference — gate.sh etc. live in $KIT, not ~/.local/bin)
if [[ -f "$KIT/tf" ]]; then
  BIN_DIR="$HOME/.local/bin"
  if mkdir -p "$BIN_DIR" 2>/dev/null; then
    # ownership check: look for our marker comment (fixed-string grep, reliable)
    # symlinks: rm first (writing through a symlink would clobber the target)
    if [[ -f "$BIN_DIR/tf" && ! -L "$BIN_DIR/tf" ]] && ! grep -qF '# rig-lite tf wrapper' "$BIN_DIR/tf" 2>/dev/null; then
      echo "init-repo: $BIN_DIR/tf already exists (not ours) — left untouched" >&2
    else
      # only remove symlinks that point at OUR kit — never delete a user's own link
      if [[ -L "$BIN_DIR/tf" ]]; then
        RGTARGET="$(readlink "$BIN_DIR/tf" 2>/dev/null)"
        case "$RGTARGET" in
          */rig-lite/tf) rm -f "$BIN_DIR/tf" ;;  # ours — safe to replace
          *) echo "init-repo: $BIN_DIR/tf is a symlink to $RGTARGET (not ours) — left untouched" >&2; exit 0 ;;
        esac
      fi
      if printf '#!/usr/bin/env bash\n# rig-lite tf wrapper\nexec %q "$@"\n' "$KIT/tf" > "$BIN_DIR/tf" && chmod +x "$BIN_DIR/tf"; then
        echo "init-repo: tf wrapper installed to $BIN_DIR/tf (points at $KIT/tf)"
      else
        echo "init-repo: tf not installed — use $KIT/tf directly" >&2
      fi
    fi
  else
    echo "init-repo: cannot create $BIN_DIR — use $KIT/tf directly" >&2
  fi
fi
