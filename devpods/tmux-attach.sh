#!/bin/bash
# tmux-attach.sh — self-healing entry into the 'workspace' tmux session.
# Called by the devcontainer terminal profile (and the bashrc guard) so a
# user lands INSIDE tmux, never in a bare shell racing postAttach:
#
#   1. session already up            → attach immediately
#   2. postAttach still building     → wait (up to TF_ATTACH_TIMEOUT secs)
#   3. timeout / postAttach failed   → bootstrap it ourselves via
#                                      tmux-workspace.sh --no-attach
#
# Flags (composable): --inline attach without exec (bashrc guard — detaching
# returns to the shell); --probe wait+bootstrap only, never attach (tests).
# Env: TF_ATTACH_TIMEOUT seconds to wait before bootstrapping (default 300 —
# post-setup.sh alone can run for minutes on a cold codespace).
set -uo pipefail

SESSION=workspace
TIMEOUT="${TF_ATTACH_TIMEOUT:-300}"
INLINE=0
PROBE=0
for arg in "$@"; do
    case "$arg" in
        --inline) INLINE=1 ;;
        --probe)  PROBE=1 ;;
        *) echo "unknown flag: $arg (use --inline, --probe)" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TW="$HERE/tmux-workspace.sh"

# Already inside tmux (bashrc guard double-check, nested profile runs) — done.
[ -n "${TMUX:-}" ] && exit 0

# No tty and not probing: we cannot attach here — leave a pointer, don't hang.
if [ "$PROBE" -eq 0 ] && ! { [ -t 0 ] && [ -t 1 ]; }; then
    echo "tmux-attach: not a terminal — attach manually with: tmux attach -t $SESSION" >&2
    exit 1
fi

# 1/2: wait for postAttach to deliver the session (progress dots, one message)
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "⏳ waiting for the '$SESSION' tmux session (postAttach may still be building)…"
    waited=0
    while ! tmux has-session -t "$SESSION" 2>/dev/null; do
        sleep 2; waited=$((waited + 2))
        echo -n .
        [ "$waited" -ge "$TIMEOUT" ] && break
    done
    echo
fi

# 3: still nothing → bootstrap ourselves, serialized against postAttach's own
# tmux-workspace.sh run via flock so two racers can't double-create windows.
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ -f "$TW" ]; then
        echo "🔧 session not up after ${TIMEOUT}s — building it now"
        exec 9>"${TMPDIR:-/tmp}/tf-tmux-bootstrap.lock"
        flock -w 120 9 || true    # lock wait is best-effort; bootstrap is idempotent
        bash "$TW" --no-attach || true
    else
        echo "❌ $TW not found — build manually: bash devpods/tmux-workspace.sh" >&2
        exit 1
    fi
fi

tmux has-session -t "$SESSION" 2>/dev/null || { echo "❌ no '$SESSION' session after bootstrap" >&2; exit 1; }
[ "$PROBE" -eq 1 ] && exit 0

echo "✅ attaching to '$SESSION' (Ctrl-b d detaches · Ctrl-b 0-3 switches windows)"
if [ "$INLINE" -eq 1 ]; then
    # bashrc mode: return to the shell on detach instead of closing the terminal
    tmux attach-session -t "$SESSION"
else
    exec tmux attach-session -t "$SESSION"
fi
