#!/usr/bin/env bash
# test-tmux-workspace.sh — behavioral tests for the tmux workspace policy.
# Runs FULLY ISOLATED on a throwaway tmux socket (PATH-shimmed `tmux -L twtest`)
# — the production session/socket is never touched. Needs tmux (Codespace/CI).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TW="$HERE/../tmux-workspace.sh"
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT   # baseline cleanup; upgraded post-shim below
command -v tmux >/dev/null 2>&1 || { echo "tmux not installed — tests skipped"; exit 0; }
REAL_TMUX="$(command -v tmux)"
printf '#!/usr/bin/env bash
exec %s -L twtest "$@"
' "$REAL_TMUX" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"
# trap set ONLY after the shim is live: it must kill the ISOLATED server, never
# production (early exits above happen before any trap exists)
trap '"$SHIM/tmux" kill-server 2>/dev/null || true; rm -rf "$SHIM"' EXIT
export WORKSPACE_FOLDER="$(cd "$HERE/../.." && pwd)"
FAIL=0
tmux kill-server 2>/dev/null || true   # no stale twtest server may back test 2
t() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected $2, got $3"; FAIL=1; fi; }

# 1 · unknown flag → exit 2
bash "$TW" --bogus >/dev/null 2>&1; t "unknown flag → 2" 2 $?
# 2 · first run builds the session headless
bash "$TW" --no-attach >/dev/null 2>&1; t "build → 0" 0 $?
tmux has-session -t workspace 2>/dev/null; t "session exists" 0 $?
N=$(tmux list-windows -t workspace -F '#{window_name}' | wc -l | tr -d ' ')
t "4 windows built" 4 "$N"
# 3 · re-attach keeps the session AND the pane process (PID-verified: the
# marker file alone would exist even if the session had been nuked)
tmux send-keys -t workspace:0 "touch $SHIM/marker; sleep 30" C-m; sleep 1
PANE_PID="$(tmux list-panes -t workspace:0 -F '#{pane_pid}' | head -1)"
OUT="$(bash "$TW" --no-attach 2>&1)"; t "re-attach → 0" 0 $?
[[ "$OUT" == *"keeping it"* ]] && echo "✓ kept-session message" || { echo "✗ expected keep message"; FAIL=1; }
kill -0 "$PANE_PID" 2>/dev/null && echo "✓ pane process survived the re-attach (PID $PANE_PID alive)" \
  || { echo "✗ pane process died on re-attach"; FAIL=1; }
# 4 · monitor window death self-heals on the next run (when the monitor is
# available; without python3/token-monitor the script warns and skips healing)
tmux kill-window -t workspace:2 2>/dev/null || true
HEALOUT="$(bash "$TW" --no-attach 2>&1)"; sleep 1
if command -v python3 >/dev/null 2>&1 && [ -f "$WORKSPACE_FOLDER/devpods/scripts/token-monitor.py" ]; then
  # pane_current_command is portable (pane_start_command is not on older tmux);
  # a healed monitor window runs python3 as its pane process
  HEAL_CMD="$(tmux list-panes -t workspace:Claude-Monitor -F '#{pane_current_command}' 2>/dev/null | head -1)"
  [[ "$HEAL_CMD" == python3* ]] \
    && echo "✓ monitor window self-healed (pane runs python3)" || { echo "✗ healed window isn't the monitor: '$HEAL_CMD'"; FAIL=1; }
else
  [[ "$HEALOUT" == *"no self-heal"* ]] && echo "✓ no-monitor warn path taken" \
    || { echo "✗ expected the no-self-heal warning"; FAIL=1; }
fi
# 5 · --rebuild recreates a fresh session (pane PID changes = true recreation)
OLD_PID="$(tmux list-panes -t workspace:0 -F '#{pane_pid}' | head -1)"
bash "$TW" --rebuild --no-attach >/dev/null 2>&1; t "rebuild → 0" 0 $?
tmux list-windows -t workspace -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ rebuild built fresh workspace" || { echo "✗ rebuild missing windows"; FAIL=1; }
sleep 0.5
NEW_PID="$(tmux list-panes -t workspace:0 -F '#{pane_pid}' | head -1)"
[[ -n "$OLD_PID" && "$NEW_PID" != "$OLD_PID" ]] && echo "✓ rebuild recreated the session (pane PID changed)" \
  || { echo "✗ rebuild did not recreate (same pane PID)"; FAIL=1; }

# 6a · recorder auth guard handles jq's false (regression: // treated false as falsy)
if command -v jq >/dev/null 2>&1; then
  GUARD_OUT="$(printf '{"loggedIn": false}' | jq -r '.loggedIn|tostring' 2>/dev/null || true)"
  [[ "$GUARD_OUT" == "false" ]] && echo "✓ jq false-handling correct" || { echo "✗ jq false regression: '$GUARD_OUT'"; FAIL=1; }
  GUARD_OUT2="$(printf '{"loggedIn": true}' | jq -r '.loggedIn|tostring' 2>/dev/null || true)"
  [[ "$GUARD_OUT2" == "true" ]] && echo "✓ jq true-handling correct" || { echo "✗ jq true regression"; FAIL=1; }
fi

# 6a2 · the recorder's auth guard, against the REAL captured CLI output
AG="$HERE/../../demo/auth-guard.sh"
if [ -f "$AG" ]; then
  AGDIR="$(mktemp -d)"
  mk_fake_claude() { printf '%s\n' "$1" > "$AGDIR/response.json"; printf '#!/usr/bin/env bash\ncat "%s/response.json"\n' "$AGDIR" > "$AGDIR/claude"; chmod +x "$AGDIR/claude"; }
  REAL_JSON_FALSE='{"loggedIn": false, "authMethod": "none", "apiProvider": "firstParty"}'
  REAL_JSON_TRUE='{"loggedIn": true, "authMethod": "oauth"}'
  mk_fake_claude "$REAL_JSON_FALSE"
  PATH="$AGDIR:$PATH" bash "$AG" >/dev/null 2>&1 \
    && echo "✓ auth guard passes loggedIn:false" || { echo "✗ auth guard rejects a logged-out box"; FAIL=1; }
  mk_fake_claude "$REAL_JSON_TRUE"
  PATH="$AGDIR:$PATH" bash "$AG" >/dev/null 2>&1 && { echo "✗ auth guard passed an AUTHENTICATED box"; FAIL=1; } \
    || echo "✓ auth guard aborts on authenticated"
  mk_fake_claude 'not json at all'
  PATH="$AGDIR:$PATH" bash "$AG" >/dev/null 2>&1 && { echo "✗ auth guard passed garbage"; FAIL=1; } \
    || echo "✓ auth guard aborts on garbage"
  rm -rf "$AGDIR"
fi

# 6 · devcontainer postCreate contract (JSON-level)
if command -v python3 >/dev/null 2>&1 && [ -f "$HERE/../../.devcontainer/devcontainer.json" ]; then
  PC="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["postCreateCommand"])' "$HERE/../../.devcontainer/devcontainer.json")"
  [[ "$PC" == *"exit 1"* ]] && echo "✓ postCreate fails loudly on apt failure" || { echo "✗ postCreate missing exit 1"; FAIL=1; }
  [[ "$PC" == *"chmod +x \${containerWorkspaceFolder}/devpods/*.sh 2>/dev/null || true"* ]] \
  && echo "✓ chmod is failure-tolerant" || { echo "✗ chmod intolerance"; FAIL=1; }
  [[ "$PC" == *"if sudo apt-get update && sudo apt-get install"* ]] && echo "✓ setup gated on apt success" || { echo "✗ apt gate regressed"; FAIL=1; }
  # bashrc guard: every interactive shell self-attaches into the session
  [[ "$PC" == *"tmux-attach.sh\" --inline"* ]] && echo "✓ bashrc auto-attach guard installed" || { echo "✗ bashrc guard missing"; FAIL=1; }
  # terminal profile: self-healing attach, never a bare-shell fallback
  PROF="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["customizations"]["vscode"]["settings"]["terminal.integrated.profiles.linux"]["tmux-workspace"]["args"][1])' "$HERE/../../.devcontainer/devcontainer.json")"
  [[ "$PROF" == *tmux-attach.sh* ]] && echo "✓ terminal profile uses self-healing attach" || { echo "✗ profile still raw-attaches: $PROF"; FAIL=1; }
  if bash -n <<<"$PC" 2>/dev/null; then echo "✓ postCreateCommand parses as bash"; else echo "✗ postCreateCommand is not valid bash"; FAIL=1; fi
else
  echo "⚠ devcontainer contract check SKIPPED (python3 or devcontainer.json unavailable)"
fi

# 7 · tmux-attach.sh — the self-healing entry the profile + bashrc guard call
TA="$HERE/../tmux-attach.sh"
if [ -f "$TA" ]; then
  # 7a · unknown flag → exit 2 (same contract as tmux-workspace.sh)
  bash "$TA" --bogus >/dev/null 2>&1; t "attach: unknown flag → 2" 2 $?
  # 7b · probe with the session up → 0, instantly (no bootstrap needed)
  tmux has-session -t workspace 2>/dev/null || bash "$TW" --no-attach >/dev/null 2>&1
  bash "$TA" --probe >/dev/null 2>&1; t "attach: probe with session up → 0" 0 $?
  # 7c · no tty without --probe → exit 1 with a pointer, never a hang
  bash "$TA" >/dev/null 2>&1; t "attach: no-tty refuses to hang → 1" 1 $?
  # 7d · the race the profile exists for: session dead, short timeout →
  # waits, times out, bootstraps it itself via tmux-workspace.sh
  tmux kill-session -t workspace 2>/dev/null || true
  TF_ATTACH_TIMEOUT=4 bash "$TA" --probe >/dev/null 2>&1; t "attach: race lost → self-bootstrap → 0" 0 $?
  tmux has-session -t workspace 2>/dev/null; t "attach: bootstrapped session exists" 0 $?
  N=$(tmux list-windows -t workspace -F '#{window_name}' | wc -l | tr -d ' ')
  t "attach: bootstrap built 4 windows" 4 "$N"
  # 7e · already-inside-tmux → immediate clean exit (guard double-check);
  # typed into a real pane so tmux's own TMUX env does the talking
  if tmux has-session -t workspace 2>/dev/null; then
    tmux send-keys -t workspace:0 "bash $TA --probe; echo RC=\$?" C-m
    sleep 1
    R="$(tmux capture-pane -pt workspace:0 2>/dev/null | grep -o 'RC=[0-9]*' | tail -1)"
    [[ "$R" == "RC=0" ]] && echo "✓ attach: inside-tmux short-circuits" || { echo "✗ inside-tmux path failed: '$R'"; FAIL=1; }
  fi
else
  echo "⚠ tmux-attach tests SKIPPED (devpods/tmux-attach.sh missing)"
fi

# teardown: the isolated socket dies with this test
tmux kill-server 2>/dev/null || true
echo
[[ $FAIL -eq 0 ]] && echo "tmux-workspace tests: ALL PASS" || { echo "tmux-workspace tests: FAILURES"; exit 1; }
