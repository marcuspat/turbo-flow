#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Turbo Flow v4 — DevPod/Codespace bootstrapper
# Installs Claude Code + Ruflo v3.5 + MCP servers + shell aliases
###############################################################################

LOG="/tmp/turbo-flow-setup.log"
START=$(date +%s)

log()  { printf '%s\n' "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
ok()   { log "  ✓ $*"; }
warn() { log "  ⚠ $*"; }
err()  { log "  ✗ $*"; }
elapsed() { echo "$(( $(date +%s) - START ))s"; }

log "Turbo Flow v4 — setup starting"

###############################################################################
# STEP 1: Claude Code
###############################################################################

if command -v claude &>/dev/null; then
    ok "Claude Code already present ($(claude --version 2>/dev/null || echo 'installed'))"
else
    log "Installing Claude Code..."
    if npm install -g @anthropic-ai/claude-code >> "$LOG" 2>&1; then
        ok "Claude Code installed"
    else
        warn "claude-code npm install failed — install manually per https://docs.anthropic.com"
    fi
fi

###############################################################################
# STEP 2: Ruflo v3.5
###############################################################################

if command -v ruflo &>/dev/null; then
    ok "Ruflo already present"
else
    log "Installing Ruflo v3.5..."
    if npm install -g ruflo@3.5.0 >> "$LOG" 2>&1; then
        ok "Ruflo v3.5 installed"
    else
        warn "Ruflo install failed — plugins will be skipped"
    fi
fi

###############################################################################
# STEP 3: MCP servers
###############################################################################

MCP_INSTALLED=0

install_mcp() {
    local name="$1" cmd="$2"
    if claude mcp list 2>/dev/null | rg -q "$name"; then
        ok "MCP $name already registered"
        return 0
    fi
    if claude mcp add "$name" -- $cmd >> "$LOG" 2>&1; then
        ok "MCP $name registered"
        ((MCP_INSTALLED++)) || true
    else
        warn "MCP $name registration failed"
    fi
}

# Context7 (documentation lookup)
install_mcp "context7" "npx -y @upstash/context7-mcp@latest"

###############################################################################
# STEP 4: Shell aliases
###############################################################################

ALIASES_FILE="$HOME/.bash_aliases"

cat >> "$ALIASES_FILE" << 'ALIASEOF'

# Turbo Flow aliases
alias tf='ruflo'
alias tfp='ruflo plugins'
alias tfs='ruflo status'
alias tfx='ruflo exec'
ALIASEOF

ok "Aliases written to $ALIASES_FILE"

###############################################################################
# STEP 5: CLAUDE.md template
###############################################################################

if [ ! -f "CLAUDE.md" ] || rg -q '<PROJECT_NAME>' CLAUDE.md 2>/dev/null; then
    REPO_NAME=$(basename "$(pwd)")
    cat > CLAUDE.md << CLAUDEEOF
# CLAUDE.md — ${REPO_NAME}

## Build
\`\`\`\nbash
cargo build --workspace  # Rust projects
# or
npm run build       # Node projects
\`\`\`

## Test
\`\`\`\nbash
cargo test --workspace  # Rust
# or
npm test               # Node
\`\`\`

## Conventions
- Commit messages: conventional commits
- Branch: main
CLAUDEEOF
    ok "CLAUDE.md created for ${REPO_NAME}"
else
    ok "CLAUDE.md already exists"
fi

###############################################################################
# Done
###############################################################################

log "Setup complete in $(elapsed)"
log "MCP servers registered: $MCP_INSTALLED"
log "Run 'claude' to start coding."
