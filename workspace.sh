#!/usr/bin/env bash
# workspace.sh — the 5-window tmux rig: boot, and tmux fires with the rig live.
#
#   1  claude      the Anthropic reviewer (plain claude)
#   2  builder     claude-glm when the GLM path was chosen (the zai family — a real
#                  cross-family pair with window 1); otherwise plain claude with the
#                  ruflo plugins loaded, labeled honestly (same family as w1)
#   3  codex       the OpenAI lane (ruflo reachable via its MCP wiring)
#   4  tokens      rig-lite/tokens.py --watch — live burn across the harnesses
#   5  shell       a free pane
#
# Usage:
#   workspace.sh            build the session if absent, then attach (interactive)
#   workspace.sh --build    build only (no attach) — used by tests and postCreate
#   workspace.sh --plan     print the window plan (test/inspection hook)
#
# Opt out of auto-attach: TF_NO_TMUX=1 (the boot hook and attach() both honor it).
# Idempotent and non-destructive: a live session is NEVER mutated; missing CLIs
# degrade their window to a hint shell; every tmux call is checked (fail-closed).
set -u

TF_HOME="${TF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SESSION="turboflow"
TFQ="$(printf '%q' "$TF_HOME")"

builder_cmd() { # window 2: claude-glm when the GLM path was wired; else plain claude
  if command -v claude-glm >/dev/null 2>&1; then
    printf 'claude-glm'
  else
    printf 'claude'
  fi
}

plan() {
  printf '1  claude      claude (Anthropic reviewer)\n'
  printf '2  builder     %s (claude-glm when the GLM path was chosen; ruflo plugins loaded)\n' "$(builder_cmd)"
  printf '3  codex       codex (ruflo via MCP)\n'
  printf '4  tokens      rig-lite/tokens.py --watch (live multi-harness dashboard)\n'
  printf '5  shell       bash\n'
}

hint() { exec bash; }  # window bodies print their own guidance before settling

w_claude() {
  command -v claude >/dev/null 2>&1 || { echo "claude not installed — run: ./setup-harness.sh"; hint; }
  exec claude
}
w_builder() {
  if command -v claude-glm >/dev/null 2>&1 && exec claude-glm; then :; fi
  command -v claude >/dev/null 2>&1 || { echo "no harness CLI installed — run: ./setup-harness.sh"; hint; }
  echo "(same family as window 1 — choose the GLM path in ./setup-harness.sh for a cross-family builder)"
  exec claude
}
w_codex() {
  command -v codex >/dev/null 2>&1 || { echo "codex not installed — run: ./setup-harness.sh"; hint; }
  exec codex
}
w_tokens() {
  command -v python3 >/dev/null 2>&1 || { echo "python3 missing — the tokens dashboard needs it"; hint; }
  exec python3 "$TF_HOME/rig-lite/tokens.py" --watch
}
w_shell()  { exec bash; }

type_plugin_proof() { # wait for the REPL, never answer prompts, then type /plugin
  local i pane
  for i in $(seq 1 30); do
    sleep 1
    pane="$(tmux capture-pane -p -t "$SESSION:claude+ruflo" 2>/dev/null || true)"
    [[ -z "$pane" ]] && continue
    case "$pane" in
      *"Do you trust"*|*"trust the files"*) return 0 ;;  # never touch a trust prompt
    esac
    # positive READY marker: the input box border AND the help hint in the status area
    if printf '%s' "$pane" | tail -4 | grep -q '^│' && printf '%s' "$pane" | grep -q 'help'; then
      tmux send-keys -t "$SESSION:claude+ruflo" -l '/plugin'
      sleep 0.5
      tmux send-keys -t "$SESSION:claude+ruflo" Enter
      return 0
    fi
  done
}

build() {
  command -v tmux >/dev/null 2>&1 || { echo "workspace: tmux not installed — the 5-window rig needs it (container postCreate installs it)" >&2; return 1; }
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "workspace: session '$SESSION' already live — left untouched"; return 0
  fi
  local w2n="claude+ruflo"
  command -v claude-glm >/dev/null 2>&1 && w2n="builder"
  local w
  printf -v w 'TF_HOME=%q bash -c '"'"'source "$TF_HOME/workspace.sh"; w_%s'"'"'' "$TF_HOME" claude
  tmux new-session -d -s "$SESSION" -n claude  "$w" || { echo "workspace: new-session failed" >&2; return 1; }
  printf -v w 'TF_HOME=%q bash -c '"'"'source "$TF_HOME/workspace.sh"; w_%s'"'"'' "$TF_HOME" builder
  tmux new-window  -t "$SESSION:" -n "$w2n"    "$w" || { echo "workspace: window $w2n failed" >&2; return 1; }
  printf -v w 'TF_HOME=%q bash -c '"'"'source "$TF_HOME/workspace.sh"; w_%s'"'"'' "$TF_HOME" codex
  tmux new-window  -t "$SESSION:" -n codex     "$w" || { echo "workspace: window codex failed" >&2; return 1; }
  printf -v w 'TF_HOME=%q bash -c '"'"'source "$TF_HOME/workspace.sh"; w_%s'"'"'' "$TF_HOME" tokens
  tmux new-window  -t "$SESSION:" -n tokens    "$w" || { echo "workspace: window tokens failed" >&2; return 1; }
  printf -v w 'TF_HOME=%q bash -c '"'"'source "$TF_HOME/workspace.sh"; w_%s'"'"'' "$TF_HOME" shell
  tmux new-window  -t "$SESSION:" -n shell     "$w" || { echo "workspace: window shell failed" >&2; return 1; }
  # proof beat: only for the plain-claude builder window (claude-glm has its own
  # readiness shape), only when that claude is authenticated, only when the REPL
  # shows its READY input box — never on trust prompts or any other dialog
  if [[ "$w2n" = "claude+ruflo" && "${TF_WORKSPACE_PROOF:-1}" = "1" ]] \
     && claude auth status >/dev/null 2>&1; then
    ( type_plugin_proof ) >/dev/null 2>&1 &
  fi
  echo "workspace: session '$SESSION' built — 5 windows (w2: $w2n)"
  return 0
}

attach() {
  [[ "${TF_NO_TMUX:-}" = "1" ]] && { echo "workspace: TF_NO_TMUX set — staying out of tmux"; return 0; }
  [[ -t 0 && -t 1 ]] || { echo "workspace: not interactive — build only"; return 0; }
  [[ -n "${TMUX:-}" ]] && { echo "workspace: already inside tmux"; return 0; }
  tmux has-session -t "$SESSION" 2>/dev/null || build >/dev/null || return 1
  exec tmux attach -t "$SESSION"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then  # dispatch only when executed; windows source the helpers
  case "${1:-}" in
    --build) TF_WORKSPACE_PROOF=0 build ;;
    --plan)  plan ;;
    --help|-h) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' ;;
    "")      build >/dev/null; attach ;;
    *) echo "workspace: unknown flag '$1' (try --help)" >&2; exit 1 ;;
  esac
fi
