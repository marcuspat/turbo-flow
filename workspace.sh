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
#   workspace.sh --build    build only (no attach) — used by the suite's live test;
#                           the boot hook and humans use the bare form
#   workspace.sh --plan     print the window plan (test/inspection hook)
#
# Opt out entirely: TF_NO_TMUX=1 disables the boot menu AND the auto-attach (the
# hook checks it before anything runs; attach() and the bare invocation check too).
# Idempotent and non-destructive: a live session is NEVER mutated; missing CLIs
# degrade their window to a hint shell; every tmux call is checked (fail-closed).
# Note: window commands assume a POSIX-ish default-shell with bash available; very
# exotic TF_HOME paths (which %q would $'...'-quote) are out of scope.
set -u

TF_HOME="${TF_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SESSION="turboflow"

w2_name() { # window 2's REAL session name — the single source plan and build share
  if command -v claude-glm >/dev/null 2>&1; then printf 'builder'; else printf 'claude+ruflo'; fi
}
builder_cmd() { # what window 2 runs: claude-glm when the GLM path was wired; else claude
  if command -v claude-glm >/dev/null 2>&1; then printf 'claude-glm'; else printf 'claude'; fi
}

plan() {
  printf '1  claude        claude (Anthropic reviewer)\n'
  printf '2  %-12s %s (claude-glm when the GLM path was chosen; ruflo plugins loaded)\n' "$(w2_name)" "$(builder_cmd)"
  printf '3  codex         codex (ruflo via MCP)\n'
  printf '4  tokens        rig-lite/tokens.py --watch (live multi-harness dashboard)\n'
  printf '5  shell         bash\n'
}

hint() { exec bash; }  # window bodies print their own guidance before settling

w_env() { # always load nvm when it exists — windows run `bash -c` (no bashrc) and
  # may inherit neither the installer's PATH nor nvm; a system node on PATH is NOT
  # proof the CLIs are reachable (they may live in the user's nvm prefix).
  # nvm.sh is not set-u safe: sourced with -u relaxed inside a subshell.
  [[ -s "$HOME/.nvm/nvm.sh" ]] || return 0
  ( set +u; . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 )
  return 0
}

w_claude() {
  w_env
  command -v claude >/dev/null 2>&1 || { echo "claude not installed — run: ./setup-harness.sh"; hint; }
  exec claude
}
w_builder() { # claude-glm when wired (its exec fails closed by design); else plain claude
  w_env
  if command -v claude-glm >/dev/null 2>&1; then
    exec claude-glm
  fi
  command -v claude >/dev/null 2>&1 || { echo "no harness CLI installed — run: ./setup-harness.sh"; hint; }
  echo "(same family as window 1 — choose the GLM path in ./setup-harness.sh for a cross-family builder)"
  exec claude
}
w_codex() {
  w_env
  command -v codex >/dev/null 2>&1 || { echo "codex not installed — run: ./setup-harness.sh"; hint; }
  exec codex
}
w_tokens() {
  command -v python3 >/dev/null 2>&1 || { echo "python3 missing — the tokens dashboard needs it"; hint; }
  exec python3 "$TF_HOME/rig-lite/tokens.py" --watch
}
w_shell()  { exec bash; }


build() {
  command -v tmux >/dev/null 2>&1 || { echo "workspace: tmux not installed — the 5-window rig needs it (container postCreate installs it)" >&2; return 1; }
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "workspace: session '$SESSION' already live — left untouched"; return 0
  fi
  local w2n
  w2n="$(w2_name)"
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
    --build) build ;;
    --plan)  plan ;;
    --help|-h) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 && !/^#/ {exit}' "$0" ;;
    "")      if [[ "${TF_NO_TMUX:-}" = "1" ]]; then echo "workspace: TF_NO_TMUX set — nothing to do"; exit 0; fi; build >/dev/null; attach ;;
    *) echo "workspace: unknown flag '$1' (try --help)" >&2; exit 1 ;;
  esac
fi
