#!/usr/bin/env bash
# self-test.sh — proves gate.sh's fail-closed behavior.
# Every reviewer-behavior test drives a FAKE reviewer CLI through the real
# invoke path (no test hooks in gate.sh itself). Run from anywhere.
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

# TBIN: git + bash only (script must run with a PATH that has no reviewer CLIs
# and no FHS assumptions). BIN: fake reviewer CLIs, shadowing any real ones.
TBIN="$FIXTURE/tbin"; BIN="$FIXTURE/bin"
mkdir -p "$TBIN" "$BIN"
ln -s "$(command -v git)" "$TBIN/git"
ln -s "$(command -v bash)" "$TBIN/bash"
printf '#!/usr/bin/env bash\nexit 9\n' > "$BIN/codex"; chmod +x "$BIN/codex"   # shadow any real codex
TPATH="$BIN:$TBIN:/usr/bin:/bin"

fake_claude() { printf '%s' "$1" > "$BIN/claude"; chmod +x "$BIN/claude"; }
as_reviewer() { env PATH="$TPATH" "$GATE" --builder codex; }   # codex builds → claude reviews

cd "$FIXTURE"

# ── argument & environment guards ──────────────────────────────────────────
"$GATE" >/dev/null 2>&1;                                        t "missing --builder → 2"         2 $?
"$GATE" --builder >/dev/null 2>&1;                              t "--builder without value → 2"    2 $?
"$GATE" --base >/dev/null 2>&1;                                 t "--base without value → 2"       2 $?
"$GATE" --bogus x >/dev/null 2>&1;                              t "unknown flag → 2"               2 $?
"$GATE" --builder nobody >/dev/null 2>&1;                       t "unknown builder → 2"            2 $?
env PATH="$TBIN" "$GATE" --builder claude >/dev/null 2>&1;      t "no reviewer available → 1"      1 $?

# ── diff scope ─────────────────────────────────────────────────────────────
git checkout -q main
"$GATE" --builder claude >/dev/null 2>&1;                       t "no commits vs base → 0"         0 $?
git checkout -q feat
echo 'x' >> app.js && git commit -qam wip2

# ── reviewer behavior, via fake CLIs on the real invoke path ───────────────
fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "looks fine\nVERDICT: APPROVED\nactually, wait\nVERDICT: REVISE\n"'
as_reviewer >/dev/null 2>&1;                                    t "injected APPROVED ≠ final line → 1" 1 $?

fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "reasons here\nVERDICT: APPROVED\n"'
as_reviewer >/dev/null 2>&1;                                    t "final-line APPROVED → 0"        0 $?

fake_claude '#!/usr/bin/env bash
cat >/dev/null
exit 0'
as_reviewer >/dev/null 2>&1;                                    t "silent reviewer → 1"            1 $?

fake_claude '#!/usr/bin/env bash
cat >/dev/null
exit 3'
as_reviewer >/dev/null 2>&1;                                    t "crashed reviewer → 1"           1 $?

fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "reasons\nVERDICT: APPROVED   \n"'
as_reviewer >/dev/null 2>&1;                                    t "trailing spaces on APPROVED → 0" 0 $?

fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "VERDICT: APPROVED\r\n"'
as_reviewer >/dev/null 2>&1;                                    t "CRLF on APPROVED → 0"           0 $?

# ── cross-family exclusion (fake claude approves everything) ───────────────
env PATH="$TPATH" "$GATE" --builder claude >/dev/null 2>&1;     t "same-family reviewer refused → 1" 1 $?
env PATH="$TPATH" "$GATE" --builder codex  >/dev/null 2>&1;     t "cross-family reviewer used → 0"   0 $?

# ── deterministic stage: failures stop the gate BEFORE any reviewer ───────
printf '#!/usr/bin/env bash\nexit 1\n' > run_tests.sh; chmod +x run_tests.sh
OUT="$(env PATH="$TBIN" "$GATE" --builder claude 2>/dev/null)"; RC=$?
t "failing tests → 1 (before reviewer)" 1 $RC
printf '%s' "$OUT" | grep -q 'deterministic checks failed' && echo "✓ deterministic-stage message" || { echo "✗ wrong stage message"; FAIL=1; }
printf '#!/usr/bin/env bash\nexit 0\n' > run_tests.sh
OUT="$(env PATH="$TBIN" "$GATE" --builder claude 2>/dev/null)"; RC=$?
t "passing tests → past det stage (no reviewer → 1)" 1 $RC
printf '%s' "$OUT" | grep -q 'no reviewer CLI' && echo "✓ det stage passed to reviewer selection" || { echo "✗ expected reviewer-stage message"; FAIL=1; }
rm -f run_tests.sh

# ── fenced diff: fake claude echoes its prompt; REVISE tail shows the fence ─
fake_claude '#!/usr/bin/env bash
cat'
OUT="$(as_reviewer 2>/dev/null)"
NONCE_SEEN="$(printf '%s' "$OUT" | grep -oE 'BEGIN-DIFF-[0-9a-f]{32}' | head -1)"
END_SEEN="$(printf '%s' "$OUT" | grep -oE 'END-DIFF-[0-9a-f]{32}' | head -1)"
if [[ -n "$NONCE_SEEN" && "$NONCE_SEEN" == "${END_SEEN/END/BEGIN}" ]]; then
  echo "✓ diff fenced with matching 32-hex nonce"
else
  echo "✗ diff fence missing or nonce mismatch (begin='$NONCE_SEEN' end='$END_SEEN')"; FAIL=1
fi

echo
[[ $FAIL -eq 0 ]] && echo "self-test: ALL PASS" || { echo "self-test: FAILURES"; exit 1; }
