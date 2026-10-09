#!/usr/bin/env bash
# workspace.sh — the 5-window agentic workspace: boot, and tmux fires with the rig live.
#
#   1  claude        plain Anthropic reviewer
#   2  claude+ruflo  ruflo plugins pre-installed (setup-harness's CLI path — the
#                    slash commands were already executed non-interactively at
#                    install time, so the REPL opens with ruflo loaded; a /plugin
#                    proof is typed in once the REPL is up and authenticated)
#   3  codex         OpenAI lane (ruflo reachable via its MCP wiring)
#   4  tokens        rig-lite/tokens.py --watch — live burn across the harnesses
#   5  shell         free pane for whatever comes next
#
# Usage:
#   workspace.sh            build the session if absent, then attach (interactive)
#   workspace.sh --build    build only (no attach) — used by tests and postCreate
#   workspace.sh --plan     print the window plan (test/inspection hook)
#
# Idempotent and non-destructive: an existing session is NEVER mutated (your live
# windows are yours); missing CLIs degrade their window to a hint shell.
set -u

TF_HOME="${TF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SESSION="turboflow"

plan() {
  cat <<'EOF'
1  claude        claude (Anthropic reviewer)
2  claude+ruflo  claude with ruflo plugins pre-installed (+ /plugin proof when authed)
3  codex         codex (ruflo via MCP)
4  tokens        rig-lite/tokens.py --watch (live multi-harness dashboard)
5  shell         bash
EOF
}

hint() { # <msg> — keeps a window open with guidance when its CLI is missing
  printf '%s\n\n' "$1"; exec bash
}

w_claude()      { command -v claude  >/dev/null 2>&1 && exec claude  || hint "claude not installed — run: ./setup-harness.sh"; }
w_codex()       { command -v codex   >/dev/null 2>&1 && exec codex   || hint "codex not installed — run: ./setup-harness.sh"; }
w_tokens()      { exec python3 "$TF_HOME/rig-lite/tokens.py" --watch; }
w_shell()       { exec bash; }

build() {
  command -v tmux >/dev/null 2>&1 || { echo "workspace: tmux not installed — the 5-window rig needs it (container postCreate installs it)" >&2; return 1; }
  tmux has-session -t "$SESSION" 2>/dev/null && { echo "workspace: session '$SESSION' already live — left untouched"; return 0; }
  tmux new-session -d -s "$SESSION" -n claude        "TF_HOME='$TF_HOME' bash -c 'source \"$TF_HOME/workspace.sh\"; w_claude'"
  tmux new-window  -t "$SESSION:" -n claude+ruflo    "TF_HOME='$TF_HOME' bash -c 'source \"$TF_HOME/workspace.sh\"; w_claude'"
  tmux new-window  -t "$SESSION:" -n codex           "TF_HOME='$TF_HOME' bash -c 'source \"$TF_HOME/workspace.sh\"; w_codex'"
  tmux new-window  -t "$SESSION:" -n tokens          "TF_HOME='$TF_HOME' bash -c 'source \"$TF_HOME/workspace.sh\"; w_tokens'"
  tmux new-window  -t "$SESSION:" -n shell           "TF_HOME='$TF_HOME' bash -c 'source \"$TF_HOME/workspace.sh\"; w_shell'"
  # window 2: once the REPL is up AND authenticated, type the /plugin proof
  ( sleep 10
    if claude auth status >/dev/null 2>&1; then
      tmux send-keys -t "$SESSION:claude+ruflo" -l '/plugin'
      sleep 0.4
      tmux send-keys -t "$SESSION:claude+ruflo" Enter
    fi
  ) >/dev/null 2>&1 &
  echo "workspace: session '$SESSION' built — 5 windows"
  return 0
}

attach() {
  [[ -t 0 && -t 1 ]] || { echo "workspace: not interactive — build only"; return 0; }
  [[ -n "${TMUX:-}" ]] && { echo "workspace: already inside tmux"; return 0; }
  tmux has-session -t "$SESSION" 2>/dev/null || build >/dev/null || return 1
  exec tmux attach -t "$SESSION"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then  # dispatch only when executed; windows source the helpers
  case "${1:-}" in
    --build) build ;;
    --plan)  plan ;;
    --help|-h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
    "")      build >/dev/null; attach ;;
    *) echo "workspace: unknown flag '$1' (try --help)" >&2; exit 1 ;;
  esac
fi
