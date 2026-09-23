#!/bin/bash
set -ex
# Get the directory where this script is located
readonly DEVPOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure required variables have defaults (derived from this script's location,
# so bare runs without env vars land in the right workspace)
: "${WORKSPACE_FOLDER:=$(cd "$DEVPOD_DIR/.." && pwd)}"
: "${DEVPOD_WORKSPACE_FOLDER:=$WORKSPACE_FOLDER}"
: "${AGENTS_DIR:=$WORKSPACE_FOLDER/agents}"

# flags (composable): --rebuild recreates the session (kills running panes);
# --no-attach never attaches (postAttach/CI/plain-ssh mode)
REBUILD=0; NOATTACH=0
for arg in "$@"; do
    case "$arg" in
        --rebuild)   REBUILD=1 ;;
        --no-attach) NOATTACH=1 ;;
        *) echo "unknown flag: $arg (use --rebuild, --no-attach)" >&2; exit 2 ;;
    esac
done

echo "=== Starting TMux Workspace ==="
echo "WORKSPACE_FOLDER: $WORKSPACE_FOLDER"
echo "DEVPOD_WORKSPACE_FOLDER: $DEVPOD_WORKSPACE_FOLDER"
echo "AGENTS_DIR: $AGENTS_DIR"
echo "DEVPOD_DIR: $DEVPOD_DIR"
# Install tmux if not available
if ! command -v tmux >/dev/null 2>&1; then
    echo "📦 Installing tmux and htop..."
    sudo apt-get update -qq
    sudo apt-get install -y tmux htop
    echo "✅ tmux and htop installed successfully"
fi
# Verify tmux installation
if ! command -v tmux >/dev/null 2>&1; then
    echo "❌ tmux installation failed - cannot continue"
    exit 1
fi
# Ensure we're in the workspace directory
cd "$WORKSPACE_FOLDER"

# quality-of-life options are idempotent globals — applied on every run
# AFTER a session exists (tmux needs a live server), incl. kept sessions
apply_qol() {
    tmux set-option -g history-limit 50000
    tmux set-option -g mouse on
    tmux set-window-option -g mode-keys vi
}

# Session policy: an existing session is KEPT (postAttach runs on every client
# attach — recreating would kill running Claude panes each reconnect); use
# --rebuild to force recreation. Kept sessions skip the build below but still
# reach the attach logic so interactive runs land in the session.
SKIP_BUILD=0
if [ "$REBUILD" -eq 1 ]; then
    tmux kill-session -t workspace 2>/dev/null || true
elif tmux has-session -t workspace 2>/dev/null; then
    echo "✅ workspace session already running — keeping it (--rebuild to recreate)"
    SKIP_BUILD=1
    apply_qol   # kept session may predate current option defaults
    # self-heal: the monitor window closes when its process dies — recreate it
    if ! tmux list-windows -t workspace -F '#{window_name}' 2>/dev/null | grep -q '^Claude-Monitor'; then
        if command -v python3 >/dev/null 2>&1 && [ -f "$WORKSPACE_FOLDER/devpods/scripts/token-monitor.py" ]; then
            # append at the next free index — never kill a live window; the name carries it
            if tmux new-window -t workspace -n "Claude-Monitor" -c "$WORKSPACE_FOLDER" \
                -d "python3 devpods/scripts/token-monitor.py --watch 5"; then
                # restore the canonical position (index 2 is free — that's why
                # we healed); a no-op if occupancy shifted
                tmux move-window -s Claude-Monitor -t workspace:2 2>/dev/null || true
                echo "🔁 monitor window was dead — recreated"
            else
                echo "⚠ monitor self-heal failed — recreate manually: tmux new-window -t workspace -n Claude-Monitor" >&2
            fi
        else
            echo "⚠ monitor window missing and python3/token-monitor unavailable — no self-heal" >&2
        fi
    fi
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
    # Create new session with first window for Claude
    tmux new-session -d -s workspace -n "Claude-1" -c "$WORKSPACE_FOLDER"
    apply_qol
    # Create second window for Claude
    tmux new-window -t workspace:1 -n "Claude-2" -c "$WORKSPACE_FOLDER"
    # Create third window for Claude monitor
    tmux new-window -t workspace:2 -n "Claude-Monitor" -c "$WORKSPACE_FOLDER"
    # Create fourth window for htop
    tmux new-window -t workspace:3 -n "htop" -c "$WORKSPACE_FOLDER"
    # Start htop in window 3
    if command -v htop >/dev/null 2>&1; then
        tmux send-keys -t workspace:3 "htop" C-m
    else
        tmux send-keys -t workspace:3 "echo 'htop not installed. Run: sudo apt-get install -y htop'" C-m
    fi
    # Set up Claude Monitor window — live token dashboard (ported from the rig).
    # The window IS the monitor process: tmux's own -c uses the same
    # $WORKSPACE_FOLDER the guard checks, so the constant relative command resolves
    # by construction — no typed shell, no interpolation. Fallbacks recreate the
    # window as a shell pane for environments without python3.
    TOKEN_MONITOR="$WORKSPACE_FOLDER/devpods/scripts/token-monitor.py"
    if command -v python3 >/dev/null 2>&1 && [ -f "$TOKEN_MONITOR" ]; then
        tmux kill-window -t workspace:2 2>/dev/null || true
        tmux new-window -t workspace:2 -n "Claude-Monitor" -c "$WORKSPACE_FOLDER" \
            -d "python3 devpods/scripts/token-monitor.py --watch 5"
    elif command -v claude-monitor >/dev/null 2>&1; then
        tmux kill-window -t workspace:2 2>/dev/null || true
        tmux new-window -t workspace:2 -n "Claude-Monitor" -c "$WORKSPACE_FOLDER" -d
        tmux send-keys -t workspace:2 "claude-monitor" C-m
    elif command -v claude-usage-cli >/dev/null 2>&1; then
        tmux kill-window -t workspace:2 2>/dev/null || true
        tmux new-window -t workspace:2 -n "Claude-Monitor" -c "$WORKSPACE_FOLDER" -d
        tmux send-keys -t workspace:2 "claude-usage-cli" C-m
    else
        tmux send-keys -t workspace:2 "echo 'Claude monitor tools not installed'" C-m
    fi
    # Send helpful messages to Claude windows
    tmux send-keys -t workspace:0 "echo '=== Claude Window 1 Ready ==='" C-m
    tmux send-keys -t workspace:0 "echo 'Workspace: $WORKSPACE_FOLDER'" C-m
    tmux send-keys -t workspace:0 "echo 'Agents: $AGENTS_DIR'" C-m
    tmux send-keys -t workspace:0 "echo 'DevPod Dir: $DEVPOD_DIR'" C-m
    tmux send-keys -t workspace:0 "echo ''" C-m
    tmux send-keys -t workspace:0 "echo 'Load mandatory agents with:'" C-m
    tmux send-keys -t workspace:0 "echo 'cat \$AGENTS_DIR/doc-planner.md'" C-m
    tmux send-keys -t workspace:0 "echo 'cat \$AGENTS_DIR/microtask-breakdown.md'" C-m
    tmux send-keys -t workspace:1 "echo '=== Claude Window 2 Ready ==='" C-m
    tmux send-keys -t workspace:1 "echo 'Workspace: $WORKSPACE_FOLDER'" C-m
    tmux send-keys -t workspace:1 "echo 'DevPod Dir: $DEVPOD_DIR'" C-m
    # Select the first window
    tmux select-window -t workspace:0
    echo "✅ TMux workspace 'workspace' created successfully!"
fi

# --no-attach: explicit headless/postAttach mode. Without it, attach only
# from an interactive terminal — CI/plain-ssh runs succeed with a pointer
# instead of dying on "not a terminal".
if [ "$NOATTACH" -eq 1 ] || ! { [ -t 0 ] && [ -t 1 ]; }; then
    echo "✅ Session 'workspace' ready — attach with: tmux attach -t workspace"
else
    echo "📝 Attaching to tmux session..."
    tmux attach-session -t workspace
fi
