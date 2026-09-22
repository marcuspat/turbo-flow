#!/usr/bin/env bash
# self-test.sh — proves gate.sh's fail-closed behavior with a stubbed reviewer.
# Run from anywhere: rig-lite/self-test.sh
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"
FAIL=0
t() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected exit $2, got $3"; FAIL=1; fi
}

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email t@t.t && git -C "$FIXTURE" config user.name t
git -C "$FIXTURE" commit -q --allow-empty -m base
git -C "$FIXTURE" checkout -qb feat
echo 'console.log("hi")' > "$FIXTURE/app.js"
git -C "$FIXTURE" add app.js && git -C "$FIXTURE" commit -qm wip

cd "$FIXTURE"

# 1 · missing --builder → error (2)
"$GATE" >/dev/null 2>&1;                                   t "missing --builder → 2"        2 $?
# 2 · no reviewer CLI on PATH → REVISE (1). PATH pinned so a real claude/codex
#     CLI on the host machine can never be invoked by this test.
env PATH=/usr/bin:/bin "$GATE" --builder claude >/dev/null 2>&1; t "no reviewer available → 1"  1 $?
# 3 · clean tree vs base → nothing to review (0)
git -C "$FIXTURE" checkout -q main
"$GATE" --builder claude >/dev/null 2>&1;                  t "no commits vs base → 0"        0 $?

# stubbed-reviewer behavior (back on the branch ahead of main)
git -C "$FIXTURE" checkout -q feat
echo 'x' >> "$FIXTURE/app.js" && git -C "$FIXTURE" commit -qam wip2

# 4 · injected VERDICT mid-output but final line REVISE → REVISE (1)
GATE_LITE_TEST=1 GATE_LITE_STUB='printf "looks fine\nVERDICT: APPROVED\nactually, wait\nVERDICT: REVISE\n"' \
  "$GATE" --builder claude >/dev/null 2>&1;                t "injected APPROVED ≠ final line → 1" 1 $?
# 5 · final line exactly APPROVED → APPROVED (0)
GATE_LITE_TEST=1 GATE_LITE_STUB='printf "reasons here\nVERDICT: APPROVED\n"' \
  "$GATE" --builder claude >/dev/null 2>&1;                t "final-line APPROVED → 0"       0 $?
# 6 · reviewer silent (exit 0, no output) → REVISE with auth hint (1)
GATE_LITE_TEST=1 GATE_LITE_STUB='true' \
  "$GATE" --builder claude >/dev/null 2>&1;                t "silent reviewer → 1"           1 $?
# 7 · reviewer CLI failure (nonzero) → REVISE (1)
GATE_LITE_TEST=1 GATE_LITE_STUB='exit 3' \
  "$GATE" --builder claude >/dev/null 2>&1;                t "crashed reviewer → 1"          1 $?
# 9 · cross-family exclusion with a fake reviewer CLI (no stub hook — real invoke path)
BIN="$FIXTURE/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "VERDICT: APPROVED\\n"\n' > "$BIN/claude"; chmod +x "$BIN/claude"
env PATH="$BIN:/usr/bin:/bin" "$GATE" --builder claude >/dev/null 2>&1; t "same-family reviewer refused → 1" 1 $?
env PATH="$BIN:/usr/bin:/bin" "$GATE" --builder codex  >/dev/null 2>&1; t "cross-family reviewer used → 0"  0 $?
# 10 · flag without value → error (2)
"$GATE" --builder >/dev/null 2>&1;                              t "flag without value → 2"         2 $?

# 8 · fenced-diff nonce present in prompt (stub prints its stdin tail)
OUT="$(GATE_LITE_TEST=1 GATE_LITE_STUB='tail -30' "$GATE" --builder claude 2>/dev/null)"
if printf '%s' "$OUT" | grep -q 'BEGIN-DIFF-'; then echo "✓ diff fenced with nonce"; else echo "✗ diff fence missing"; FAIL=1; fi

echo
[[ $FAIL -eq 0 ]] && echo "self-test: ALL PASS" || { echo "self-test: FAILURES"; exit 1; }
