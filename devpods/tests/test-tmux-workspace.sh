#!/usr/bin/env bash
# test-tmux-workspace.sh — behavioral tests for the tmux workspace policy.
# Runs FULLY ISOLATED on a throwaway tmux socket (PATH-shimmed `tmux -L twtest`)
# — the production session/socket is never touched. Needs tmux (Codespace/CI).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TW="$HERE/../tmux-workspace.sh"
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT
printf '#!/usr/bin/env bash\nexec /usr/bin/tmux -L twtest "$@"\n' > "$SHIM/tmux"
chmod +x "$SHIM/tmux"
if ! command -v tmux >/dev/null 2>&1; then echo "tmux not installed — tests skipped"; exit 0; fi
export PATH="$SHIM:$PATH"
export WORKSPACE_FOLDER="$(cd "$HERE/../.." && pwd)"
FAIL=0
t() { if [[ "$2" == "$3" ]]; then echo "✓ $1"; else echo "✗ $1 — expected $2, got $3"; FAIL=1; fi; }

# 1 · unknown flag → exit 2
bash "$TW" --bogus >/dev/null 2>&1; t "unknown flag → 2" 2 $?
# 2 · first run builds the session headless
bash "$TW" --no-attach >/dev/null 2>&1; t "build → 0" 0 $?
tmux has-session -t workspace 2>/dev/null; t "session exists" 0 $?
N=$(tmux list-windows -t workspace -F '#{window_name}' | wc -l | tr -d ' ')
t "4 windows built" 4 "$N"
# 3 · re-attach keeps the session AND the pane process
tmux send-keys -t workspace:0 "touch $SHIM/marker; sleep 30" C-m; sleep 1
OUT="$(bash "$TW" --no-attach 2>&1)"; t "re-attach → 0" 0 $?
[[ "$OUT" == *"keeping it"* ]] && echo "✓ kept-session message" || { echo "✗ expected keep message"; FAIL=1; }
[[ -e "$SHIM/marker" ]] && echo "✓ pane process survived the re-attach" || { echo "✗ pane process died"; FAIL=1; }
# 4 · monitor window death self-heals on the next run
tmux kill-window -t workspace:2 2>/dev/null || true
bash "$TW" --no-attach >/dev/null 2>&1; sleep 1
tmux list-windows -t workspace -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ monitor window self-healed" || { echo "✗ monitor not healed"; FAIL=1; }
# 5 · --rebuild recreates a fresh session (marker process from the old one gone)
bash "$TW" --rebuild --no-attach >/dev/null 2>&1; t "rebuild → 0" 0 $?
tmux list-windows -t workspace -F '#{window_name}' | grep -q '^Claude-Monitor' \
  && echo "✓ rebuild built fresh workspace" || { echo "✗ rebuild missing windows"; FAIL=1; }
sleep 1
[[ -e "$SHIM/marker" ]] && echo "✗ rebuild left the old pane's marker (session not recreated)" && FAIL=1 \
  || echo "✓ rebuild recreated the session (old pane gone)"

# teardown: the isolated socket dies with this test
tmux kill-server 2>/dev/null || true
echo
[[ $FAIL -eq 0 ]] && echo "tmux-workspace tests: ALL PASS" || { echo "tmux-workspace tests: FAILURES"; exit 1; }
