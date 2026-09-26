#!/usr/bin/env bash
# self-test.sh — proves the kit's fail-closed behavior: gate.sh verdicts,
# wt.sh worktree lifecycle, init-repo.sh onboarding.
# Every reviewer-behavior test drives a FAKE reviewer CLI through the real
# invoke path (no test hooks in gate.sh itself). Run from anywhere.
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
GATE="$KIT/gate.sh"
WT="$KIT/wt.sh"
INIT="$KIT/init-repo.sh"
FAIL=0
t() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected exit $2, got $3"; FAIL=1; fi
}

FIXTURE="$(mktemp -d)"      # the git fixture — fake CLI dirs live OUTSIDE it
BINS="$(mktemp -d)"
WFIX="$(mktemp -d)"         # wt.sh + init-repo.sh fixtures (real git, no PATH tricks)
WFIX="$(cd "$WFIX" && pwd -P)"   # physical path: git resolves /var → /private/var on macOS
IFIX="$(mktemp -d)"
MFIX=""                     # master-fallback fixture, created in the wt section
trap 'rm -rf "$FIXTURE" "$BINS" "$WFIX" "$IFIX" "$MFIX"' EXIT
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
# shellcheck into the hermetic PATH too — macOS brew/static locations aren't
# under /usr/bin:/bin, and the shellcheck-gated section must reach it (skip stays honest)
command -v shellcheck >/dev/null 2>&1 && ln -s "$(command -v shellcheck)" "$TBIN/shellcheck"
printf '#!/usr/bin/env bash\nexit 9\n' > "$BIN/codex"; chmod +x "$BIN/codex"   # shadow any real codex
TPATH="$BIN:$TBIN:/usr/bin:/bin"

fake_claude() { printf '%s' "$1" > "$BIN/claude"; chmod +x "$BIN/claude"; }
# fresh ahead-of-main state for any test that needs one — no shared arithmetic
fresh_ahead() {
  git checkout -q -B feat main 2>/dev/null || git checkout -q feat
  echo "f$RANDOM$RANDOM" >> app.js
  git add -A && git commit -qm "fixture $RANDOM"
}
as_reviewer() { env PATH="$TPATH" "$GATE" --builder codex; }   # codex builds → claude reviews

cd "$FIXTURE"

# ── argument & environment guards ──────────────────────────────────────────
"$GATE" >/dev/null 2>&1;                                        t "missing --builder → 2"         2 $?
"$GATE" --builder >/dev/null 2>&1;                              t "--builder without value → 2"    2 $?
"$GATE" --base >/dev/null 2>&1;                                 t "--base without value → 2"       2 $?
"$GATE" --bogus x >/dev/null 2>&1;                              t "unknown flag → 2"               2 $?
"$GATE" --builder nobody >/dev/null 2>&1;                       t "unknown builder → 2"            2 $?
env PATH="$TBIN" "$GATE" --builder claude >/dev/null 2>&1;      t "no reviewer available → 1"      1 $?

# (the old "no commits vs base → 0" case is now the fail-closed --base-at-HEAD guard → 2, covered below)
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
fresh_ahead
OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
t "--no-exec → reviewer still runs → 0" 0 $RC
printf '%s' "$OUT" | grep -q -- '--no-exec: untrusted branch' && echo "✓ --no-exec skip markers shown" || { echo "✗ missing --no-exec markers"; FAIL=1; }

# ── secret redaction on echoed reviewer output ─────────────────────────────
fresh_ahead
fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "reasons: used token: sk-live-abcdef123456 here\nBearer abcdef123\nbare: ghp_AbCdEfGhIjKlMnOpQrSt123456789012345678\nkey AKIAIOSFODNN7EXAMPLE8888\nVERDICT: REVISE\n"'
OUT="$(as_reviewer 2>/dev/null)"
if printf '%s' "$OUT" | grep -q 'REDACTED' && ! printf '%s' "$OUT" | grep -q 'sk-live-abcdef'; then
  echo "✓ secrets redacted in echoed reviewer output"
else
  echo "✗ secret leaked in echo"; FAIL=1
fi

# ── stderr-path redaction: crashed reviewer leaking a token in stderr ─────
fresh_ahead
fake_claude '#!/usr/bin/env bash
cat >/dev/null
echo "auth failed: token sk-live-abcdef123456 expired" >&2
exit 3'
OUT="$(as_reviewer 2>&1)"; RC=$?
t "crashed reviewer → 1" 1 $RC
if printf '%s' "$OUT" | grep -q 'REDACTED' && ! printf '%s' "$OUT" | grep -q 'sk-live-abcdef'; then
  echo "✓ stderr leak redacted on failure path"
else
  echo "✗ stderr leak survived"; FAIL=1
fi

# ── --base guards: base at/ahead of HEAD must fail closed, not pass ───────
"$GATE" --builder claude --base HEAD >/dev/null 2>&1;  t "--base HEAD → 2" 2 $?
"$GATE" --builder claude --base feat  >/dev/null 2>&1; t "--base feat (self) → 2" 2 $?
"$GATE" --builder claude --base nope >/dev/null 2>&1; t "--base missing branch → 2" 2 $?

# ── det_shellcheck: diff-scoped, deleted files ignored (needs shellcheck) ──
if command -v shellcheck >/dev/null 2>&1; then
  # approver for the SECOND test below; the FIRST asserts the det stage fails
  # BEFORE any reviewer runs — that ordering is the property under test
  fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "reasons here\nVERDICT: APPROVED\n"'
  ensure_ahead_sh() {
    git checkout -q -B feat main
    printf '#!/usr/bin/env bash\nUNUSED_VAR=hello\necho hi\n' > bad.sh   # SC2034 (warning) — survives -S warning
    printf '#!/usr/bin/env bash\necho ok\n' > good.sh
    git add -A && git commit -qm shfix
    git rm -q good.sh && git commit -qm "delete good.sh"
  }
  ensure_ahead_sh
  OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
  t "shellcheck flags bad .sh in diff → 1" 1 $RC
  printf '%s' "$OUT" | grep -q 'UNUSED_VAR' && echo "✓ shellcheck finding surfaced (by variable name — code-number agnostic)" || { echo "✗ expected shellcheck diagnostic"; FAIL=1; }
  # FIXED=ok, not FIXED=done: shellcheck -S warning flags VAR=done (SC1010,
  # reserved word as the tail of an assignment) — the "fixed" fixture must be
  # clean under the same severity the gate enforces
  printf '#!/usr/bin/env bash\nFIXED=ok\necho "$FIXED"\n' > bad.sh && git add -A && git commit -qm fixsh
  OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec 2>/dev/null)"; RC=$?
  t "shellcheck clean diff + deleted file ignored → 0" 0 $RC
else
  echo "⚠ shellcheck not installed — det_shellcheck path untested this run"
fi

# ── untrusted exit-42 must FAIL, not skip ───────────────────────────────────
fresh_ahead
printf '#!/usr/bin/env bash\nexit 42\n' > run_tests.sh; chmod +x run_tests.sh
git add -A && git commit -qm exit42
OUT="$(env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex 2>/dev/null)"; RC=$?
t "entrypoint exits 42 → FAIL (1), not skip" 1 $RC
printf '%s' "$OUT" | grep -q 'FAIL' && echo "✓ exit-42 reported as failure" || { echo "✗ expected FAIL report"; FAIL=1; }

# ── --no-exec must NOT execute the branch entrypoint ───────────────────────
fresh_ahead
fake_claude '#!/usr/bin/env bash
cat >/dev/null
printf "reasons here\nVERDICT: APPROVED\n"'
printf '#!/usr/bin/env bash\ntouch /tmp/gate-lite-noexec-probe\n' > run_tests.sh; chmod +x run_tests.sh
rm -f /tmp/gate-lite-noexec-probe
git add -A && git commit -qm probe
env PATH="$BIN:$TBIN:/usr/bin:/bin" "$GATE" --builder codex --no-exec >/dev/null 2>&1
if [[ -e /tmp/gate-lite-noexec-probe ]]; then echo "✗ --no-exec executed run_tests.sh"; FAIL=1; rm -f /tmp/gate-lite-noexec-probe
else echo "✓ --no-exec did not execute the entrypoint"; fi

# ── fenced diff: fake claude echoes its prompt; REVISE tail shows the fence ─
fresh_ahead
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

# ── wt.sh: worktree lifecycle (Law 3 made executable) ───────────────────────
git -C "$WFIX" init -q -b main
git -C "$WFIX" config user.email t@t.t && git -C "$WFIX" config user.name t
git -C "$WFIX" commit -q --allow-empty -m base

"$WT" >/dev/null 2>&1;                                            t "wt: no args → 1"        1 $?
"$WT" --help >/dev/null 2>&1;                                     t "wt: --help → 0"         0 $?
(cd "$(mktemp -d)" && "$WT" lane) >/dev/null 2>&1;                t "wt: outside a git repo → 2" 2 $?

OUT="$(cd "$WFIX" && "$WT" lane1)"; RC=$?
t "wt: create → 0" 0 $RC
[[ -d "$WFIX/.worktrees/lane1" ]] && echo "✓ wt: worktree dir created" || { echo "✗ wt: no worktree dir"; FAIL=1; }
if [[ "$OUT" == "$WFIX/.worktrees/lane1" ]]; then echo "✓ wt: prints the worktree path"; else echo "✗ wt: wrong path on stdout: $OUT"; FAIL=1; fi
git -C "$WFIX" show-ref --verify --quiet refs/heads/lane1 && echo "✓ wt: branch lane1 created" || { echo "✗ wt: branch lane1 missing"; FAIL=1; }

(cd "$WFIX" && "$WT" lane1) >/dev/null 2>&1;                      t "wt: duplicate name → 1" 1 $?
(cd "$WFIX/.worktrees/lane1" && echo wip > f.txt && git add f.txt && git commit -qm wip) >/dev/null 2>&1
t "wt: commit inside the worktree lands on its branch → 0" 0 $?
# f.txt must exist on lane1 and NOT on main (isolation is the whole point)
if git -C "$WFIX" cat-file -e lane1:f.txt 2>/dev/null && ! git -C "$WFIX" cat-file -e main:f.txt 2>/dev/null; then
  echo "✓ wt: lane1 commit isolated from main"
else
  echo "✗ wt: lane1/main isolation broken"; FAIL=1
fi

(cd "$WFIX" && "$WT" lane2 lane1) >/dev/null 2>&1;                t "wt: create from explicit base branch → 0" 0 $?
# lane1 carries the wip commit that main lacks — only a real [base] arg makes
# lane1 an ancestor of lane2; a silently-ignored base would branch off main
git -C "$WFIX" merge-base --is-ancestor lane1 lane2 && echo "✓ wt: lane2 actually cut from lane1, not main" || { echo "✗ wt: explicit base ignored"; FAIL=1; }
(cd "$WFIX" && "$WT" laneX nosuchbase) >/dev/null 2>&1;           t "wt: explicit missing base → 2" 2 $?
(cd "$WFIX" && "$WT" laneX "") >/dev/null 2>&1;                  t "wt: explicit empty base → 2"  2 $?
(cd "$WFIX" && "$WT" --list) 2>/dev/null | grep -q ".worktrees/lane1" && echo "✓ wt: --list shows the worktree" || { echo "✗ wt: --list missing worktree"; FAIL=1; }

(cd "$WFIX" && "$WT" --clean lane1) >/dev/null 2>&1;              t "wt: --clean → 0"         0 $?
[[ ! -e "$WFIX/.worktrees/lane1" ]] && echo "✓ wt: worktree dir removed" || { echo "✗ wt: dir survived --clean"; FAIL=1; }
git -C "$WFIX" show-ref --verify --quiet refs/heads/lane1 2>/dev/null && { echo "✗ wt: branch survived --clean"; FAIL=1; } || echo "✓ wt: branch removed"
(cd "$WFIX" && "$WT" --clean lane1) >/dev/null 2>&1;              t "wt: --clean again (nothing to clean) → 0" 0 $?
# honest refusal: a branch checked out in the main worktree can't be -D'd,
# and --clean must say so instead of printing a fake success
(cd "$WFIX" && git branch stucklane && git checkout -q stucklane)
OUT="$(cd "$WFIX" && "$WT" --clean stucklane 2>&1)"; RC=$?
t "wt: --clean with branch checked out elsewhere → 1 (no fake success)" 1 $RC
printf '%s' "$OUT" | grep -q "failed to delete branch" && echo "✓ wt: refusal says why" || { echo "✗ wt: refusal reason missing: $OUT"; FAIL=1; }
if printf '%s' "$OUT" | grep -q "cleaned:"; then echo "✗ wt: fake success line printed on failure"; FAIL=1; else echo "✓ wt: no success line on failure"; fi
(cd "$WFIX" && git checkout -q main && git branch -qD stucklane)
# branch exists without a worktree (partial --clean leftover) → clear refusal, not a raw git error
(cd "$WFIX" && git branch ghost) >/dev/null 2>&1
OUT="$(cd "$WFIX" && "$WT" ghost 2>&1)"; RC=$?
t "wt: create over leftover branch → 1" 1 $RC
printf '%s' "$OUT" | grep -q "already exists" && echo "✓ wt: leftover-branch refusal says why" || { echo "✗ wt: leftover-branch message missing"; FAIL=1; }
(cd "$WFIX" && git branch -qD ghost) >/dev/null 2>&1

# master fallback: repo with no main
MFIX="$(mktemp -d)"
git -C "$MFIX" init -q -b master
git -C "$MFIX" config user.email t@t.t && git -C "$MFIX" config user.name t
git -C "$MFIX" commit -q --allow-empty -m base
(cd "$MFIX" && "$WT" mk) >/dev/null 2>&1;                         t "wt: main absent → falls back to master → 0" 0 $?

# ── init-repo.sh: one-command onboarding ────────────────────────────────────
"$INIT" --help >/dev/null 2>&1;                                   t "init-repo: --help → 0"  0 $?
(cd "$(mktemp -d)" && "$INIT") >/dev/null 2>&1;                   t "init-repo: outside a git repo → 2" 2 $?

git -C "$IFIX" init -q -b main
git -C "$IFIX" config user.email t@t.t && git -C "$IFIX" config user.name t
git -C "$IFIX" commit -q --allow-empty -m base
(cd "$IFIX" && "$INIT" TestProj) >/dev/null 2>&1;                 t "init-repo: first run → 0" 0 $?
[[ -f "$IFIX/AGENTS.md" ]] && echo "✓ init-repo: AGENTS.md written" || { echo "✗ init-repo: AGENTS.md missing"; FAIL=1; }
# kit lives outside $IFIX → the constitution must have been COPIED in and the
# pointer must be repo-relative (an absolute path dies in every other clone)
[[ -f "$IFIX/rig-constitution.md" ]] && echo "✓ init-repo: constitution copied into the repo" || { echo "✗ init-repo: no copied constitution"; FAIL=1; }
grep -Eq "constitution: rig-constitution\.md" "$IFIX/AGENTS.md" && echo "✓ init-repo: relative constitution pointer" || { echo "✗ init-repo: pointer not relative"; FAIL=1; }
if grep -q "$KIT" "$IFIX/AGENTS.md"; then echo "✗ init-repo: absolute kit path committed into AGENTS.md"; FAIL=1; else echo "✓ init-repo: no absolute paths in AGENTS.md"; fi
[[ -L "$IFIX/CLAUDE.md" ]] && echo "✓ init-repo: CLAUDE.md symlinked to AGENTS.md" || { echo "✗ init-repo: CLAUDE.md not a symlink"; FAIL=1; }

cp "$IFIX/AGENTS.md" "$IFIX/.agents-before.md"
(cd "$IFIX" && "$INIT" TestProj) >/dev/null 2>&1;                 t "init-repo: rerun → 0 (idempotent)" 0 $?
cmp -s "$IFIX/AGENTS.md" "$IFIX/.agents-before.md" && echo "✓ init-repo: existing AGENTS.md never clobbered" || { echo "✗ init-repo: AGENTS.md changed on rerun"; FAIL=1; }
rm -f "$IFIX/.agents-before.md"
# the copied constitution is a template the user may adapt — reruns must not overwrite it
echo "# local amendment" >> "$IFIX/rig-constitution.md"
(cd "$IFIX" && "$INIT" TestProj) >/dev/null 2>&1;                 t "init-repo: rerun with edited constitution → 0" 0 $?
grep -q "# local amendment" "$IFIX/rig-constitution.md" && echo "✓ init-repo: edited rig-constitution.md never clobbered" || { echo "✗ init-repo: constitution edits lost on rerun"; FAIL=1; }

# ── init-repo.sh: the kit's own workflow — inside a wt.sh worktree, and from a subdir ──
# a worktree's .git is a FILE; [[ -d .git ]] would wrongly reject it
(cd "$WFIX" && "$WT" ob1) >/dev/null 2>&1
(cd "$WFIX/.worktrees/ob1" && "$INIT" WtProj) >/dev/null 2>&1;     t "init-repo: inside a wt.sh worktree → 0" 0 $?
[[ -f "$WFIX/.worktrees/ob1/AGENTS.md" ]] && echo "✓ init-repo: AGENTS.md written inside the worktree" || { echo "✗ init-repo: worktree onboarding failed"; FAIL=1; }
mkdir -p "$WFIX/src"
(cd "$WFIX/src" && "$INIT" SubProj) >/dev/null 2>&1;               t "init-repo: from a subdirectory → 0" 0 $?
if [[ -f "$WFIX/AGENTS.md" && ! -f "$WFIX/src/AGENTS.md" ]]; then echo "✓ init-repo: subdirectory run writes at the repo root, not $PWD"; else echo "✗ init-repo: subdir run scattered files"; FAIL=1; fi

rm "$IFIX/CLAUDE.md" && echo "hand-written" > "$IFIX/CLAUDE.md"
(cd "$IFIX" && "$INIT" TestProj) >/dev/null 2>&1;                 t "init-repo: real CLAUDE.md present → 0" 0 $?
[[ -f "$IFIX/CLAUDE.md" && ! -L "$IFIX/CLAUDE.md" ]] && echo "✓ init-repo: real CLAUDE.md left untouched" || { echo "✗ init-repo: clobbered a real CLAUDE.md"; FAIL=1; }

SKIPPED_SC=0
command -v shellcheck >/dev/null 2>&1 || SKIPPED_SC=1
echo
if [[ $FAIL -ne 0 ]]; then echo "self-test: FAILURES"; exit 1; fi
if [[ $SKIPPED_SC -eq 1 ]]; then
  echo "self-test: ALL PASS — ⚠ 2 shellcheck-gated checks SKIPPED (install shellcheck for full coverage)"
else
  echo "self-test: ALL PASS (full coverage)"
fi
