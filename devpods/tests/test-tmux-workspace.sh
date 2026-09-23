#!/usr/bin/env bash
# test-tmux-workspace.sh — behavioral tests for the tmux workspace policy.
# Runs FULLY ISOLATED on a throwaway tmux socket (PATH-shimmed `tmux -L twtest`)
# — the production session/socket is never touched. Needs tmux (Codespace/CI).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TW="$HERE/../tmux-workspace.sh"
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
command -v tmux >/dev/null 2>&1 || { echo "tmux not installed — tests skipped"; exit 0; }
REAL_TMUX="$(command -v tmux)"
printf '#!/usr/bin/env bash
exec %s -L twtest "$@"
' "$REAL_TMUX" > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"
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
# 4 · monitor window death self-heals on the next run
tmux kill-window -t workspace:2 2>/dev/null || true
bash "$TW" --no-attach >/dev/null 2>&1; sleep 1
tmux list-windows -t workspace -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ monitor window self-healed" || { echo "✗ monitor not healed"; FAIL=1; }
# 5 · --rebuild recreates a fresh session (pane PID changes = true recreation)
OLD_PID="$(tmux list-panes -t workspace:0 -F '#{pane_pid}' | head -1)"
bash "$TW" --rebuild --no-attach >/dev/null 2>&1; t "rebuild → 0" 0 $?
tmux list-windows -t workspace -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ rebuild built fresh workspace" || { echo "✗ rebuild missing windows"; FAIL=1; }
sleep 0.5
NEW_PID="$(tmux list-panes -t workspace:0 -F '#{pane_pid}' | head -1)"
[[ -n "$OLD_PID" && "$NEW_PID" != "$OLD_PID" ]] && echo "✓ rebuild recreated the session (pane PID changed)" \
  || { echo "✗ rebuild did not recreate (same pane PID)"; FAIL=1; }

# 6 · devcontainer postCreate contract (JSON-level)
if command -v python3 >/dev/null 2>&1 && [ -f "$HERE/../../.devcontainer/devcontainer.json" ]; then
  PC="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["postCreateCommand"])' "$HERE/../../.devcontainer/devcontainer.json")"
  [[ "$PC" == *"exit 1"* ]] && echo "✓ postCreate fails loudly on apt failure" || { echo "✗ postCreate missing exit 1"; FAIL=1; }
  [[ "$PC" == *"chmod +x"*"|| true"* ]] && echo "✓ chmod is failure-tolerant" || { echo "✗ chmod intolerance"; FAIL=1; }
  [[ "$PC" == *"if sudo apt-get update && sudo apt-get install"* ]] && echo "✓ setup gated on apt success" || { echo "✗ apt gate regressed"; FAIL=1; }
fi

# teardown: the isolated socket dies with this test
tmux kill-server 2>/dev/null || true
echo
[[ $FAIL -eq 0 ]] && echo "tmux-workspace tests: ALL PASS" || { echo "tmux-workspace tests: FAILURES"; exit 1; }
