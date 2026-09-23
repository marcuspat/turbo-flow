#!/usr/bin/env bash
# record-v4-onboarding-demo.sh — the v4 onboarding chain, re-recorded on main
# after the script fixes (npx -y unattended installs, setsid daemon,
# --no-attach tmux). Recorded via asciinema in a Codespace; warm-run first.
set -uo pipefail
cd /workspaces/turbo-flow || { echo "recorder: workspace missing — run from the turbo-flow Codespace"; exit 1; }
export WORKSPACE_FOLDER=/workspaces/turbo-flow DEVPOD_WORKSPACE_FOLDER=/workspaces/turbo-flow
export AGENTS_DIR=/workspaces/turbo-flow/agents DEVPOD_DIR=/workspaces/turbo-flow/devpods
export PATH=$HOME/.npm-global/bin:$HOME/.local/bin:$PATH

t() { # type a command char-by-char, then run it
  local cmd="$1"; local i=0
  while (( i < ${#cmd} )); do printf '%s' "${cmd:i:1}"; i=$((i+1)); sleep 0.012; done
  sleep 0.35; printf '\n'; bash -c "$cmd"
  sleep 0.55
}

clear
t 'echo "TURBO FLOW v4 — onboarding chain, re-verified 2026-09: setup → post-setup → tmux workspace"'
t 'bash devpods/setup.sh 2>&1 | tail -22'          # idempotent rerun: fast, real output
t 'bash devpods/post-setup.sh 2>&1 | grep -aE "PASS|✓|Check|verif" | head -14'
t 'bash devpods/tmux-workspace.sh --no-attach'
t 'tmux list-windows -t workspace'
t 'for w in 0 1 2 3; do echo "── window $w ──"; tmux capture-pane -p -t workspace:$w | grep -v "^$" | head -3; done'
t 'echo "✓ 4-window workspace up headless — agents build, humans merge"'
t 'echo "v5 preview + private beta → turbo-rig-beta.vercel.app"'
sleep 1.2
