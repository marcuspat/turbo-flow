#!/usr/bin/env bash
# test-tmux-workspace.sh — behavioral tests for the tmux workspace policy.
# Needs tmux (Codespace/Linux CI). Run: bash devpods/tests/test-tmux-workspace.sh
set -uo pipefail
TW="$(cd "$(dirname "$0")/.." && pwd)/tmux-workspace.sh"
WS="${TEST_TMUX_SESSION:-workspace}"
FAIL=0
t() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected $2, got $3"; FAIL=1; fi; }

export WORKSPACE_FOLDER="$(cd "$(dirname "$0")/../.." && pwd)"

# 1 · unknown flag → exit 2
bash "$TW" --bogus >/dev/null 2>&1; t "unknown flag → 2" 2 $?
# 2 · first run builds the session headless
tmux kill-session -t "$WS" 2>/dev/null || true
bash "$TW" --no-attach >/dev/null 2>&1; t "build → 0" 0 $?
tmux has-session -t "$WS" 2>/dev/null; t "session exists" 0 $?
# 3 · re-attach keeps the session and running panes
tmux send-keys -t "$WS":0 "touch /tmp/twtest-marker-$$; sleep 30" C-m; sleep 1
bash "$TW" --no-attach 2>&1 | grep -q "keeping it" && echo "✓ kept-session message" || { echo "✗ expected keep message"; FAIL=1; }
[[ -e /tmp/twtest-marker-$$ ]] && echo "✓ pane process survived" || { echo "✗ pane process died"; FAIL=1; }
# 4 · monitor window death self-heals on next run
tmux kill-window -t "$WS:2" 2>/dev/null || true
bash "$TW" --no-attach >/dev/null 2>&1; sleep 1
tmux list-windows -t "$WS" -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ monitor window self-healed" || { echo "✗ monitor not healed"; FAIL=1; }
# 5 · --rebuild recreates (fresh session, old marker process gone)
bash "$TW" --rebuild --no-attach >/dev/null 2>&1; t "rebuild → 0" 0 $?
tmux list-windows -t "$WS" -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ rebuild built fresh workspace" || { echo "✗ rebuild missing windows"; FAIL=1; }

tmux kill-session -t "$WS" 2>/dev/null || true
rm -f /tmp/twtest-marker-$$
echo
[[ $FAIL -eq 0 ]] && echo "tmux-workspace tests: ALL PASS" || { echo "tmux-workspace tests: FAILURES"; exit 1; }
