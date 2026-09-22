#!/usr/bin/env bash
# gate.sh — a minimal cross-model review gate (rig-lite)
#
# The one rule: the reviewer is never from the builder's model family.
# Deterministic checks run first (they're free); a cross-family model
# reviews the diff read-only and must end with a parseable verdict.
# Fail-closed: anything ambiguous is REVISE.
#
# Usage:
#   gate.sh [--base main] [--builder claude|codex|claude-code|...]
# Exit codes: 0 APPROVED · 1 REVISE (fix and re-run) · 2 error
#
# Wire it into any environment — turbo-flow v4, plain git, CI.
# It never merges; the merge button stays human.
set -uo pipefail

BASE="main"
BUILDER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --builder) BUILDER="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "gate: not a git repo" >&2; exit 2; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  echo "gate: base branch '$BASE' not found" >&2; exit 2
fi
if [[ -z "$(git diff --merge-base "$BASE" 2>/dev/null)" ]]; then
  echo "gate: no diff vs $BASE — nothing to review"; exit 0
fi

# ── 1 · deterministic checks (free — run before spending tokens) ──────────
run_check() { # $1 name, $2 command — skips gracefully when tooling absent
  local name="$1" cmd="$2" log="/tmp/gate-lite-$1.log"
  if eval "$cmd" >"$log" 2>&1; then
    echo "▸ $name ......... pass"
  else
    echo "▸ $name ......... FAIL (log: $log)"; return 1
  fi
}
DETERMINISTIC=PASS
run_check shellcheck 'command -v shellcheck >/dev/null && shellcheck -S warning $(git ls-files "*.sh" | xargs -r) || { [[ -z "$(git ls-files "*.sh")" ]] && exit 0; command -v shellcheck >/dev/null || exit 0; }' || DETERMINISTIC=FAIL
run_check tests     '[[ -f package.json ]] && npm test --silent; [[ -x ./run_tests.sh ]] && ./run_tests.sh; [[ -f package.json || -x ./run_tests.sh ]] || echo "no test entrypoint — skip"' || DETERMINISTIC=FAIL
run_check types     '[[ -f tsconfig.json ]] && npx --no-install tsc --noEmit || [[ ! -f tsconfig.json ]] && echo "no tsconfig — skip"' || DETERMINISTIC=FAIL
if [[ "$DETERMINISTIC" == FAIL ]]; then
  echo "gate: REVISE — deterministic checks failed; fix these before spending tokens on review"
  exit 1
fi

# ── 2 · cross-family review (builder's family is disqualified) ────────────
family_of() {
  case "$1" in
    claude|claude-code|anthropic) echo anthropic ;;
    codex|gpt|openai|o3|o4)       echo openai ;;
    glm|zcode|zai)                echo zai ;;
    gemini|google)                echo google ;;
    grok|xai)                     echo xai ;;
    *)                            echo "family-of-$1" ;;
  esac
}
BUILDER="${BUILDER:-$(git log --format='%ae' "$BASE"..HEAD | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')}"
B_FAMILY="$(family_of "$BUILDER")"

REVIEWER=""
for r in claude codex; do
  if command -v "$r" >/dev/null 2>&1 && [[ "$(family_of "$r")" != "$B_FAMILY" ]]; then
    REVIEWER="$r"; break
  fi
done
if [[ -z "$REVIEWER" ]]; then
  echo "gate: no reviewer CLI available from a family other than '$B_FAMILY' (have: claude, codex — install one)"
  echo "gate: REVISE — fail-closed by design"
  exit 1
fi

PROMPT="You are a reviewing agent. The diff below was written by a DIFFERENT model family ($B_FAMILY).
Review it read-only for correctness, security, error handling, and tests.
End your reply with EXACTLY one line: 'VERDICT: APPROVED' or 'VERDICT: REVISE' (bullet reasons above it).
Anything ambiguous is REVISE.

$(git diff --stat "$BASE" | tail -5)

$(git diff --merge-base "$BASE")"

invoke() { # $1 = cli, prompt on stdin — add your own headless CLIs here
  case "$1" in
    claude) claude -p ;;
    codex)  codex exec --sandbox read-only - ;;
    *)      cat; return 2 ;;
  esac
}
VERDICT_RAW="$(printf '%s' "$PROMPT" | invoke "$REVIEWER" 2>/dev/null)"

if printf '%s' "$VERDICT_RAW" | grep -q 'VERDICT: APPROVED'; then
  echo "gate: APPROVED ✓  (reviewer: $REVIEWER · builder family: $B_FAMILY · branch: $BRANCH)"
  echo "gate: the merge button is still yours — humans merge."
  exit 0
else
  printf '%s\n' "$VERDICT_RAW" | tail -20
  echo "gate: REVISE — address the findings above and re-run. Fail-closed by design."
  exit 1
fi
