#!/usr/bin/env bash
# setup-harness.sh — turn a fresh Codespace (or any Linux/macOS box) into an agentic
# box in one run. The kit ships NO harness on purpose; this installer ADDS one when
# you want it. Idempotent, no sudo (nvm for node, npm --global via nvm prefix).
#
#   ./setup-harness.sh            interactive: pick Claude / Codex / GLM / all
#   ./setup-harness.sh --claude   non-interactive: Claude Code + Ruflo plugins
#   ./setup-harness.sh --codex    non-interactive: Codex + Ruflo via MCP
#   ./setup-harness.sh --glm      non-interactive: Claude Code on the GLM Coding Plan + Ruflo
#
# GLM note: the ZCode app itself is GUI-only — but the GLM Coding Plan speaks the
# Anthropic protocol (docs.z.ai), so "GLM" here = Claude Code powered by your GLM
# key (builder family: zai). Keys are read hidden and written with 600 perms,
# never echoed, never committed.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

RUFLO_PLUGIN_CMDS='/plugin marketplace add ruvnet/ruflo
/plugin install ruflo-console@ruflo
/plugin install ruflo-mods@ruflo
/reload-plugins'

ensure_node() {
  if command -v node >/dev/null 2>&1 && node -v >/dev/null 2>&1; then
    ok "node $(node -v) already present"
    return 0
  fi
  say "installing node via nvm (no privileged install)…"
  NVMI="$(mktemp)" || die "mktemp failed"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o "$NVMI" \
    || die "nvm installer download failed"
  bash "$NVMI" >/dev/null 2>&1 || { rm -f "$NVMI"; die "nvm install failed"; }
  rm -f "$NVMI"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" || die "sourcing nvm failed"
  nvm install --lts >/dev/null 2>&1 || die "nvm node install failed"
  . "$NVM_DIR/nvm.sh"
  ok "node $(node -v) installed"
}

npm_global() { # npm_global <pkg…> — installs quietly under the nvm/user prefix
  npm install -g --silent "$@" >/dev/null 2>&1 \
    || die "npm install failed: $* (if node is a root-owned system install, switch to nvm and rerun)"
}

claude_logged_in() {
  claude auth status >/dev/null 2>&1
}

install_claude_cli() {
  if command -v claude >/dev/null 2>&1; then ok "claude $(claude --version 2>/dev/null | head -1) already installed"; return 0; fi
  say "installing Claude Code…"
  npm_global @anthropic-ai/claude-code
  command -v claude >/dev/null 2>&1 || die "claude CLI did not land on PATH (restart your shell and rerun)"
  ok "claude $(claude --version 2>/dev/null | head -1) installed"
}

install_ruflo_plugins() { # the four REPL commands, CLI-first with a paste-ready fallback
  say "wiring Ruflo into Claude Code…"
  if claude plugin marketplace add ruvnet/ruflo >/dev/null 2>&1; then
    PF=0
    claude plugin install ruflo-console@ruflo >/dev/null 2>&1 || { warn "ruflo-console CLI install failed"; PF=1; }
    claude plugin install ruflo-mods@ruflo   >/dev/null 2>&1 || { warn "ruflo-mods CLI install failed"; PF=1; }
    if [[ "$PF" -eq 0 ]]; then
      ok "Ruflo marketplace + console + mods installed (run /reload-plugins inside claude)"
    else
      warn "PARTIAL install — finish inside claude with the paste block below"
      printf '%s\n' "$RUFLO_PLUGIN_CMDS" | sed 's/^/      /'
    fi
    return 0
  fi
  cat <<'EOF'

  Claude Code couldn't wire the plugins non-interactively. Start claude, paste:

EOF
  printf '%s\n' "$RUFLO_PLUGIN_CMDS" | sed 's/^/      /'
}

setup_claude() {
  say "[Claude Code + Ruflo plugins]"
  ensure_node
  install_claude_cli
  if claude_logged_in; then
    ok "claude already authenticated"
  else
    warn "claude is logged out. Run:  claude   then  /login  (browser OAuth), then rerun or continue"
  fi
  install_ruflo_plugins
}

setup_codex() {
  say "[Codex + Ruflo via MCP]"
  ensure_node
  if command -v codex >/dev/null 2>&1; then
    ok "codex already installed"
  else
    say "installing Codex CLI…"
    npm_global @openai/codex
    command -v codex >/dev/null 2>&1 || die "codex CLI did not land on PATH"
    ok "codex installed"
  fi
  codex login status >/dev/null 2>&1 || warn "codex not logged in — run:  codex login  (browser)"
  mkdir -p "$HOME/.codex"
  CFG="$HOME/.codex/config.toml"
  if grep -q 'mcp_servers.ruflo' "$CFG" 2>/dev/null; then
    ok "ruflo MCP already wired in $CFG"
  else
    say "wiring ruflo MCP into $CFG…"
    cat >> "$CFG" <<'EOF'

[mcp_servers.ruflo]
command = "npx"
args = ["-y", "ruflo@latest", "mcp", "start"]
EOF
    ok "ruflo MCP wired — codex reaches ruflo's tool fleet via npx on demand"
  fi
}

setup_glm() {
  say "[GLM Coding Plan via Claude Code — builder family: zai]"
  ensure_node
  install_claude_cli
  if [[ -n "${GLM_API_KEY:-}" ]]; then
    KEY="$GLM_API_KEY"
  else
    printf '\033[1;36m▸\033[0m GLM API key (docs.z.ai console; input hidden): '
    read -rs KEY </dev/tty || read -rs KEY
    printf '\n'
  fi
  [[ -n "$KEY" ]] || die "no key given — get one at https://docs.z.ai (GLM Coding Plan)"
  printf '%s' "$KEY" | python3 "$HERE/setup-harness-glm.py" \
    || die "GLM settings merge failed"
  ok "claude now builds on GLM — the zai family, no Anthropic account"
  install_ruflo_plugins
}

menu() {
  cat <<'EOF'

  ┌────────────────────────────────────────────────────────────┐
  │            pick your harness — the kit adds one            │
  ├────────────────────────────────────────────────────────────┤
  │  1  Claude Code   Anthropic login · Ruflo as plugins       │
  │  2  Codex         OpenAI login · Ruflo via MCP             │
  │  3  GLM           Claude Code on your GLM Coding Plan key  │
  │  4  all of the above                                       │
  │  q  skip — the kit alone needs no harness                  │
  └────────────────────────────────────────────────────────────┘

EOF
  printf '  choice [1-4/q]: '
  read -r C </dev/tty || read -r C
  case "$C" in
    1) setup_claude ;;
    2) setup_codex ;;
    3) setup_glm ;;
    4) setup_claude; setup_codex; setup_glm ;;
    q|Q|"") ok "no harness installed — bash + AGENTS.md is the whole kit" ;;
    *) die "unknown choice '$C'" ;;
  esac
}

case "${1:-}" in
  --claude) setup_claude ;;
  --codex)  setup_codex ;;
  --glm)    setup_glm ;;
  --help|-h) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 && !/^#/ {exit}' "$0"; exit 0 ;;
  "")       menu ;;
  *) die "unknown flag '$1' (try --help)" ;;
esac

echo
ok "done. next: open the repo README — the gate is the same for every harness."
