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

FIXTURE="$(mktemp -d)"      # the git fixture — fake CLI dirs live OUTSIDE it
BINS="$(mktemp -d)"
trap 'rm -rf "$FIXTURE" "$BINS"' EXIT
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.email t@t.t && git -C "$FIXTURE" config user.name t
git -C "$FIXTURE" commit -q --allow-empty -m base
git -C "$FIXTURE" checkout -qb feat
echo 'console.log("hi")' > "$FIXTURE/app.js"
git -C "$FIXTURE" add app.js && git -C "$FIXTURE" commit -qm wip

# TBIN: git + bash only (script must run with a PATH that has no reviewer CLIs
# and no FHS assumptions). BIN: fake reviewer CLIs, shadowing any real ones.
TBIN="$BINS/tbin"; BIN="$BINS/bin"
mkdir -p "$TBIN" "$BIN"
ln -s "$(command -v git)" "$TBIN/git"
ln -s "$(command -v bash)" "$TBIN/bash"
for b in env grep sed tail head tr od cat mktemp; do ln -s "$(command -v "$b")" "$TBIN/$b"; done
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

# ── cross-family exclusion ─────────────────────────────────────────────────
# claude-only PATH (no codex at all): builder=claude must REFUSE the only
# available reviewer; assert the refusal message so a crash can't mask it
CBIN="$BINS/cbin"; mkdir -p "$CBIN"
cp "$BIN/claude" "$CBIN/claude"
OUT="$(env PATH="$CBIN:$TBIN:/usr/bin:/bin" "$GATE" --builder claude 2>/dev/null)"; RC=$?
t "same-family reviewer refused → 1" 1 $RC
printf '%s' "$OUT" | grep -q 'no reviewer CLI from a family other'   && echo "✓ refusal message (not a crash)" || { echo "✗ expected refusal message, got: $OUT"; FAIL=1; }
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

# ── npm branch of det_tests (host PATH, reviewer CLIs shadowed by BIN) ─────
printf '{"name":"t","version":"1.0.0","scripts":{"test":"exit 1"}}' > package.json
git add package.json && git commit -qm wip3
OUT="$(env PATH="$BIN:$PATH" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "npm failing test script → 1" 1 $RC
printf '%s' "$OUT" | grep -q 'deterministic checks failed' && echo "✓ npm failure hits det stage" || { echo "✗ npm failure not caught"; FAIL=1; }
printf '{"name":"t","version":"1.0.0","scripts":{"test":"exit 0"}}' > package.json
git commit -qam wip4
OUT="$(env PATH="$BIN:$PATH" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "npm passing test script → full gate APPROVED → 0" 0 $RC
printf '%s' "$OUT" | grep -q 'gate: APPROVED' && echo "✓ npm pass flows through to approval" || { echo "✗ expected approval"; FAIL=1; }
printf '{"name":"t","version":"1.0.0"}' > package.json
git commit -qam wip5
OUT="$(env PATH="$BIN:$PATH" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "package.json without test script → skip, gate APPROVED → 0" 0 $RC
printf '%s' "$OUT" | grep -q 'gate: APPROVED' && echo "✓ no-script skip flows through to approval" || { echo "✗ expected approval"; FAIL=1; }
git reset -q --hard HEAD~3

# ── node-without-npm: tests check skips instead of failing ─────────────────
NPBIN="$BINS/npbin"; mkdir -p "$NPBIN"
ln -s "$(command -v node)" "$NPBIN/node"
printf '{"name":"t","version":"1.0.0","scripts":{"test":"exit 0"}}' > package.json
git add -A && git commit -qm wip6
OUT2="$(env PATH="$BIN:$NPBIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "npm absent + real test script → fail-closed 1" 1 $RC
printf '%s' "$OUT2" | grep -q 'fail-closed' && echo "✓ npm-absent fail-closed message" || { echo "✗ expected fail-closed message"; FAIL=1; }
printf '{"name":"t","version":"1.0.0"}' > package.json && git add -A && git commit -qm wip7
OUT3="$(env PATH="$BIN:$NPBIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "npm absent + no test script → skip → 0" 0 $RC
git reset -q --hard HEAD~1
git reset -q --hard HEAD~1

# ── --no-exec: skips executable checks, keeps the gate flow ────────────────
OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
t "--no-exec → reviewer still runs → 0" 0 $RC
printf '%s' "$OUT" | grep -q -- '--no-exec: untrusted branch' && echo "✓ --no-exec skip markers shown" || { echo "✗ missing --no-exec markers"; FAIL=1; }

# ── --base guards: base at/ahead of HEAD must fail closed, not pass ───────
"$GATE" --builder claude --base HEAD >/dev/null 2>&1;  t "--base HEAD → 2" 2 $?
"$GATE" --builder claude --base feat  >/dev/null 2>&1; t "--base feat (self) → 2" 2 $?
"$GATE" --builder claude --base nope >/dev/null 2>&1; t "--base missing branch → 2" 2 $?

# ── det_shellcheck: diff-scoped, deleted files ignored (needs shellcheck) ──
if command -v shellcheck >/dev/null 2>&1; then
  ensure_ahead_sh() {
    git checkout -q -B feat main
    printf '#!/usr/bin/env bash\necho $UNQUOTED\n' > bad.sh
    printf '#!/usr/bin/env bash\necho ok\n' > good.sh
    git add -A && git commit -qm shfix
    git rm -q good.sh && git commit -qm "delete good.sh"
  }
  ensure_ahead_sh
  OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
  t "shellcheck flags bad .sh in diff → 1" 1 $RC
  printf '%s' "$OUT" | grep -q 'SC[0-9]' && echo "✓ shellcheck finding surfaced" || { echo "✗ expected shellcheck diagnostic"; FAIL=1; }
  printf '#!/usr/bin/env bash\necho "$FIXED"\n' > bad.sh && git add -A && git commit -qm fixsh
  OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
  t "shellcheck clean diff + deleted file ignored → 0" 0 $RC
else
  echo "⚠ shellcheck not installed — det_shellcheck path untested this run"
fi

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
