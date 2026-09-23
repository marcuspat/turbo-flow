#!/bin/bash
set -ex
# Get the directory where this script is located
readonly DEVPOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure required variables have defaults
: "${WORKSPACE_FOLDER:=$(cd "$DEVPOD_DIR/.." && pwd)}"
: "${DEVPOD_WORKSPACE_FOLDER:=$WORKSPACE_FOLDER}"
: "${AGENTS_DIR:=$WORKSPACE_FOLDER/agents}"

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
# Re-attach safety: an existing session is KEPT unless --rebuild — postAttach
# runs on every client attach, and nuking the session would kill running
# Claude panes each reconnect
REBUILD=0; NOATTACH=0
for arg in "$@"; do
    case "$arg" in
        --rebuild)   REBUILD=1 ;;
        --no-attach) NOATTACH=1 ;;
        *) echo "unknown flag: $arg (use --rebuild, --no-attach)" >&2; exit 2 ;;
    esac
done
if [ "$REBUILD" -eq 1 ]; then
    tmux kill-session -t workspace 2>/dev/null || true
elif tmux has-session -t workspace 2>/dev/null; then
    echo "✅ workspace session already running — keeping it (tmux attach -t workspace to rejoin; --rebuild to recreate)"
    exit 0
fi
# Create new session with first window for Claude
tmux new-session -d -s workspace -n "Claude-1" -c "$WORKSPACE_FOLDER"
# --- TMUX QUALITY OF LIFE SETTINGS ---
# Set large scrollback buffer
tmux set-option -g history-limit 50000
# Enable mouse mode (scroll with wheel, click to switch windows)
tmux set-option -g mouse on
# Use Vi keys in copy mode (makes searching with '/' possible)
tmux set-window-option -g mode-keys vi
# -------------------------------------
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
echo "📝 Attaching to tmux session..."
# --no-attach: explicit headless/postAttach mode. Without it, attach only
# from an interactive terminal — CI/plain-ssh runs succeed with a pointer
# instead of dying on "not a terminal".
if [ "$NOATTACH" -eq 1 ] || ! { [ -t 0 ] && [ -t 1 ]; }; then
    echo "✅ Session 'workspace' ready — attach with: tmux attach -t workspace"
else
    echo "📝 Attaching to tmux session..."
    tmux attach-session -t workspace
fi
