#!/usr/bin/env bash
# record-v4-onboarding-demo.sh — the v4 onboarding chain, ending in a REAL tmux
# attach with a scripted tour of all 4 windows (window 2 = live token monitor).
# Recorded via asciinema in a Codespace; warm-run first.
set -uo pipefail
cd /workspaces/turbo-flow || { echo "recorder: workspace missing — run from the turbo-flow Codespace"; exit 1; }
export WORKSPACE_FOLDER=/workspaces/turbo-flow DEVPOD_WORKSPACE_FOLDER=/workspaces/turbo-flow
export AGENTS_DIR=/workspaces/turbo-flow/agents DEVPOD_DIR=/workspaces/turbo-flow/devpods
export PATH=$HOME/.npm-global/bin:$HOME/.local/bin:$PATH
export TERM=xterm-256color   # tmux attach refuses dumb/absent TERM (recording pty)

# credential-free enforcement (fail-closed): the claude segment must show the
# GENUINE first-run screen. Abort unless claude exists AND explicitly reports
# NOT logged in — unknown subcommand or missing CLI are also aborts, never passes.
if ! command -v claude >/dev/null 2>&1; then
  echo "recorder: claude CLI missing — the demo requires it" >&2; exit 1
fi
AUTH_OUT="$(claude auth status 2>&1 || true)"
AUTH_LC="$(printf '%s' "$AUTH_OUT" | tr '[:upper:]' '[:lower:]')"
case " $AUTH_LC " in
  *" not logged in "*|*" logged out "*|*" no api key "*|*" not authenticated "*)
    echo "recorder: claude confirmed logged out — genuine first-run screen incoming" ;;
  *)
    echo "recorder: claude auth state unclear or authenticated — record from a credential-free Codespace" >&2
    echo "auth status said: $AUTH_OUT" >&2
    exit 1 ;;
esac

t() { # type a command char-by-char, then run it
  local cmd="$1"; local i=0
  while (( i < ${#cmd} )); do printf '%s' "${cmd:i:1}"; i=$((i+1)); sleep 0.012; done
  sleep 0.35; printf '\n'; bash -c "$cmd" || echo "⚠ recorder: STEP FAILED: $cmd"
  sleep 0.55
}

clear
t 'echo "TURBO FLOW v4 — onboarding chain: setup → post-setup → tmux workspace (4 live windows)"'
t 'bash devpods/setup.sh 2>&1 | tail -18'
t 'bash devpods/post-setup.sh 2>&1 | grep -aE "PASS|✓|verif" | head -10'
t 'bash devpods/tmux-workspace.sh --no-attach'
t 'tmux list-windows -t workspace'

# ── the finale: attach, tour every window, LAUNCH CLAUDE live ───────────────
REC_TTY="$(tty 2>/dev/null || true)"   # our tty — the driver detaches exactly this client
echo "📝 attaching — tour of all four windows, then Claude live in window 1…"
( sleep 2.5
  for w in 0 1 2 3; do tmux select-window -t workspace:$w 2>/dev/null; sleep 3.2; done
  tmux select-window -t workspace:0
  sleep 1
  # run claude in the watched window — genuine first-run UI (no API key on the
  # recording box), then exit it; that is exactly what a new user sees and does
  tmux send-keys -t workspace:0 "claude" C-m
  sleep 8
  tmux send-keys -t workspace:0 C-c
  sleep 1.5
  tmux send-keys -t workspace:0 C-c
  sleep 1
  # detach only OUR attached client (this recorder's tty) — humans stay attached
  [ -n "$REC_TTY" ] && tmux detach-client -t "$REC_TTY" 2>/dev/null ) &
timeout 90 tmux attach-session -t workspace   # bounded: a dead driver can't hang the demo
sleep 0.5

t 'echo "✓ Claude-1 · Claude-2 · live token monitor · htop — agents build, humans merge"'
t 'echo "v5 preview + private beta → turbo-rig-beta.vercel.app"'
sleep 1.2
