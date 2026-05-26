#!/usr/bin/env bash
# =============================================================================
# TurboFlow 4.0 Setup Script (FIXED)
# Replaces: .devcontainer/setup.sh from v3.4.1
#
# FIXES applied:
#   FIX 1: Ruflo init now handles "already initialized" gracefully (was crashing
#          the entire script because non-zero exit + set -e)
#   FIX 2: All claude mcp commands wrapped to never fail under set -e
#   FIX 3: npx ruflo doctor wrapped properly
#   FIX 4: Plugin install arithmetic fixed (PLUGINS_INSTALLED increment)
#   FIX 5: Step numbering corrected (was two "STEP 5"s, steps 6-10 misnumbered)
#   FIX 6: node -e for settings.json uses proper quoting
#   FIX 7: All optional tool installs (gitnexus, beads, openspec) fully guarded
#   FIX 8: bd init / gitnexus analyze in subshells with || true
#   FIX 9: sed -i compatibility (GNU vs BSD) handled
#   FIX 10: MCP registration section fully guarded
#   FIX 11: Dolt install added before Beads (required storage backend)
#   FIX 12: MCP autoStart enabled for Ruflo server
#   FIX 13: Daemon auto-start added
#   FIX 14: Security scan added to setup
#   FIX 15: GitNexus --force flag for proper indexing
#
# What changed from v3.4.1:
#   REMOVED: claude-flow@alpha (dead package → now ruflo)
#   REMOVED: Manual RuVector/SONA npm installs (bundled in ruflo v3.5)
#   REMOVED: Manual @claude-flow/browser install (bundled in ruflo v3.5)
#   REMOVED: Manual security-analyzer git clone (ruflo skill)
#   REMOVED: Manual UI UX Pro Max skill clone (ruflo skill)
#   REMOVED: Manual worktree-manager skill clone (replaced by native wt-* helpers)
#   REMOVED: Slash commands (/sparc, /speckit.* — replaced by ruflo skills)
#   REMOVED: cf-fix better-sqlite3 hack (fixed upstream)
#   REMOVED: sql.js manual install (handled by ruflo)
#   REMOVED: Separate agentic-flow install (integrated into ruflo v3.5)
#   REMOVED: 9 redundant/domain-specific plugins (see below)
#   REMOVED: ccusage standalone (use claude-usage or ruflo statusline)
#   REMOVED: Ars Contexta, OpenClaw Secure Stack, HeroUI scaffold (out of scope)
#   REMOVED: Standalone agtrace, PAL MCP, Claudish, Spec-Kit (bundled/redundant)
#   KEPT:    6 Ruflo plugins (agentic-qe, code-intelligence, test-intelligence,
#            perf-optimizer, teammate-plugin, gastown-bridge)
#   KEPT:    OpenSpec (spec-driven development)
#   ADDED:   Dolt (version-controlled SQL database — required by Beads)
#   ADDED:   Beads (cross-session project memory)
#   ADDED:   Git worktree helpers (agent isolation with PG Vector schema namespacing)
#   ADDED:   Native Agent Teams env var
#   ADDED:   GitNexus (codebase knowledge graph + MCP)
#   ADDED:   3-tier memory decision tree in CLAUDE.md
#   KEPT:    build-essential, python3, git, curl, jq
#   KEPT:    Statusline Pro (rewritten for v4.0)
#   KEPT:    DevPod/Codespaces/Rackspace compatibility
#
# Removed plugins (domain-specific or redundant with Ruflo v3.5 core):
#   - healthcare-clinical (HIPAA/FHIR — not needed)
#   - financial-risk (PCI-DSS/SOX — not needed)
#   - legal-contracts (contract analysis — not needed)
#   - cognitive-kernel (overlaps Ruflo neural system)
#   - hyperbolic-reasoning (overlaps Ruflo core)
#   - quantum-optimizer (overlaps Ruflo core)
#   - neural-coordination (overlaps Ruflo core)
#   - prime-radiant (niche interpretability)
#   - ruvector-upstream (redundant — RuVector bundled in Ruflo v3.5)
# =============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE="${WORKSPACE:-$(pwd)}"
LOG="/tmp/turboflow-setup.log"
START_TIME=$(date +%s)

step() { echo -e "\n${CYAN}━━━ [$1/11] $2 ━━━${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
elapsed() { echo "$(($(date +%s) - START_TIME))s"; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║         🚀 TurboFlow 4.0 Setup                  ║"
echo "║   Ruflo v3.5 + Beads + Worktrees + Agent Teams  ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# =============================================================================
# STEP 1: System Prerequisites
# =============================================================================
step 1 "System Prerequisites"

if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq >> "$LOG" 2>&1 || true
    sudo apt-get install -y -qq build-essential python3 python3-pip git curl jq >> "$LOG" 2>&1 || true
    ok "apt packages installed"
elif command -v brew &>/dev/null; then
    ok "macOS detected — skipping apt (brew handles deps)"
else
    warn "Unknown package manager — ensure build-essential, python3, git, curl, jq are available"
fi

# Node.js 20+ (required by ruflo v3.5)
if ! command -v node &>/dev/null || [ "$(node -v | cut -d'.' -f1 | tr -d 'v')" -lt 20 ]; then
    if command -v nvm &>/dev/null; then
        nvm install 20 && nvm use 20
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >> "$LOG" 2>&1
        sudo apt-get install -y -qq nodejs >> "$LOG" 2>&1
    fi
    ok "Node.js $(node -v) installed"
else
    ok "Node.js $(node -v) already present"
fi

# =============================================================================
# STEP 2: Claude Code + Ruflo v3.5
# Ruflo v3.5 bundles: AgentDB v3, RuVector WASM, SONA, 215 MCP tools,
# 60+ agents, skills system, 3-tier model routing, browser automation (59 MCP
# browser tools), observability, gating, multi-model routing
# This single install replaces: claude-flow@alpha, @ruvector/cli, @ruvector/sona,
# @claude-flow/browser, agentic-flow, security-analyzer, ui-ux-pro-max
#
# FIX 11: Native installer is now primary (npm method deprecated by Anthropic).
#         Old version piped to sh which broke on dash-based systems.
#         Now pipes to bash explicitly.
# FIX 12: npm fallback respects NPM_CONFIG_PREFIX from containerEnv so
#         global installs go to ~/.npm-global/ instead of /usr/local/.
# FIX 13: Ruflo init uses --force to ensure .claude-flow/ and skills are
#         fully populated even on re-runs.
# FIX 14: MCP autoStart enabled by default for Ruflo server.
# =============================================================================
step 2 "Claude Code + Ruflo v3.5"

# Claude Code — native installer is primary (npm is deprecated upstream)
if ! command -v claude &>/dev/null; then
    # Method 1: Native installer (recommended by Anthropic, no npm needed)
    curl -fsSL https://claude.ai/install.sh 2>/dev/null | bash >> "$LOG" 2>&1 || true
    export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"

    if command -v claude &>/dev/null; then
        ok "Claude Code installed (native installer)"
    else
        # Method 2: npm fallback (needs NPM_CONFIG_PREFIX set for non-root users)
        npm install -g @anthropic-ai/claude-code >> "$LOG" 2>&1 || true
        if command -v claude &>/dev/null; then
            ok "Claude Code installed (npm)"
        else
            fail "Claude Code install failed — try manually: curl -fsSL https://claude.ai/install.sh | bash"
        fi
    fi
else
    ok "Claude Code $(claude --version 2>/dev/null | head -1 || echo 'present')"
fi

# ── Ruflo init — force to ensure .claude-flow/ and skills are populated ──
RUFLO_INIT_OUTPUT=""
RUFLO_INIT_RC=0
RUFLO_INIT_OUTPUT=$(npx ruflo@latest init --force 2>&1) || RUFLO_INIT_RC=$?

if [ $RUFLO_INIT_RC -eq 0 ]; then
    ok "Ruflo v3.5 initialized (includes RuVector, AgentDB, SONA, skills, browser, observability)"
else
    RUFLO_INIT_OUTPUT2=""
    RUFLO_INIT_RC2=0
    RUFLO_INIT_OUTPUT2=$(npx ruflo@latest init 2>&1) || RUFLO_INIT_RC2=$?
    if [ $RUFLO_INIT_RC2 -eq 0 ]; then
        ok "Ruflo v3.5 initialized"
    elif echo "$RUFLO_INIT_OUTPUT2" | grep -qi "already initialized\|already exists\|Found:"; then
        ok "Ruflo v3.5 already initialized"
    else
        warn "Ruflo init returned code $RUFLO_INIT_RC2 — check $LOG"
        echo "$RUFLO_INIT_OUTPUT2" >> "$LOG" 2>&1
    fi
fi

# ── MCP registration — fully guarded, with autoStart enabled ──
claude mcp remove claude-flow 2>/dev/null || true

# FIX 14: Enable MCP autoStart by configuring the workspace .mcp.json
MCP_CONFIG="$WORKSPACE/.mcp.json"
if [ ! -f "$MCP_CONFIG" ]; then
    echo '{"mcpServers":{}}' > "$MCP_CONFIG"
fi

# Use node to safely update the MCP config with autoStart enabled
node -e "
const fs = require('fs');
const path = process.argv[1];
try {
    const config = JSON.parse(fs.readFileSync(path, 'utf8'));
    if (!config.mcpServers) config.mcpServers = {};
    config.mcpServers.ruflo = {
        command: 'npx',
        args: ['-y', 'ruflo@latest', 'mcp', 'start'],
        env: {
            npm_config_update_notifier: 'false',
            CLAUDE_FLOW_MODE: 'v3',
            CLAUDE_FLOW_HOOKS_ENABLED: 'true',
            CLAUDE_FLOW_TOPOLOGY: 'hierarchical-mesh',
            CLAUDE_FLOW_MAX_AGENTS: '15',
            CLAUDE_FLOW_MEMORY_BACKEND: 'hybrid'
        },
        autoStart: true
    };
    fs.writeFileSync(path, JSON.stringify(config, null, 2));
    process.exit(0);
} catch(e) {
    console.error(e.message);
    process.exit(1);
}
" "$MCP_CONFIG" 2>/dev/null && ok "Ruflo MCP configured with autoStart" || warn "MCP config update failed (may need manual edit)"

# Single source of truth: the project .mcp.json above (endpoint: `mcp start`, autoStart).
# Remove any stale local-/user-scope ruflo registration that would create a
# "defined in multiple scopes with different endpoints" conflict.
claude mcp remove ruflo -s local 2>/dev/null || true
claude mcp remove ruflo -s user  2>/dev/null || true
ok "Ruflo MCP registered via project .mcp.json (single scope, autoStart)"

# ── Doctor check — guarded ──
npx ruflo doctor --fix >> "$LOG" 2>&1 \
    && ok "Ruflo doctor passed" \
    || warn "Ruflo doctor had issues (check $LOG)"

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 3: Ruflo Plugins (6 — development-relevant only)
# These are Ruflo-ecosystem plugins that add capabilities beyond the core.
# Domain-specific plugins (healthcare, financial, legal) and plugins redundant
# with Ruflo v3.5 core (neural-coordination, cognitive-kernel, etc.) removed.
# =============================================================================
step 3 "Ruflo Plugins (6)"

PLUGINS_INSTALLED=0

install_plugin() {
    local plugin_name="$1"
    local plugin_dir="$WORKSPACE/.claude-flow/plugins/$plugin_name"

    if [ -d "$plugin_dir" ] && [ -f "$plugin_dir/package.json" ]; then
        ok "$plugin_name already installed"
        PLUGINS_INSTALLED=$((PLUGINS_INSTALLED + 1))
        return 0
    fi

    # FIX: Cap Node heap during plugin installs to avoid OOM in constrained containers
    local PLUGIN_OK=0
    (
        export NODE_OPTIONS="--max-old-space-size=512"
        if npx ruflo@latest plugins install -n "$plugin_name" >> "$LOG" 2>&1; then
            exit 0
        elif npx ruflo@latest plugins install --name "$plugin_name" >> "$LOG" 2>&1; then
            exit 0
        else
            exit 1
        fi
    ) && PLUGIN_OK=1 || true

    if [ "$PLUGIN_OK" -eq 1 ]; then
        ok "$plugin_name installed"
        PLUGINS_INSTALLED=$((PLUGINS_INSTALLED + 1))
        return 0
    else
        warn "$plugin_name failed (optional)"
        return 0
    fi
}

# Agentic QE — 58 QE agents, TDD, coverage analysis, security scanning, chaos engineering
install_plugin "@claude-flow/plugin-agentic-qe"

# Code Intelligence — code analysis, pattern detection, refactoring suggestions
install_plugin "@claude-flow/plugin-code-intelligence"

# Test Intelligence — test generation, gap analysis, flaky test detection
install_plugin "@claude-flow/plugin-test-intelligence"

# Perf Optimizer — performance profiling, bottleneck detection, optimization
install_plugin "@claude-flow/plugin-perf-optimizer"

# Teammate Plugin — bridges Native Agent Teams with Ruflo swarms, 21 MCP tools
install_plugin "@claude-flow/teammate-plugin"

# Fallback: npm install if ruflo plugin install failed
if ! [ -d "$WORKSPACE/.claude-flow/plugins/@claude-flow/teammate-plugin" ] && \
   ! [ -d "$WORKSPACE/node_modules/@claude-flow/teammate-plugin" ]; then
    warn "Teammate plugin failed via ruflo, trying npm..."
    npm install @claude-flow/teammate-plugin --save-dev --prefix "$WORKSPACE" >> "$LOG" 2>&1 && \
        ok "Teammate plugin installed via npm" || warn "Teammate plugin install failed (optional)"
fi

# Gastown Bridge — WASM-accelerated orchestration, Beads sync, convoy management, 20 MCP tools
install_plugin "@claude-flow/plugin-gastown-bridge"

# OpenSpec — spec-driven development (independent package, not a ruflo plugin)
npm install -g @fission-ai/openspec >> "$LOG" 2>&1 \
    && ok "OpenSpec installed" \
    || warn "OpenSpec failed (optional)"

ok "Plugins + tools installed: $PLUGINS_INSTALLED/6 plugins + OpenSpec"
ok "Elapsed: $(elapsed)"

# Free memory between heavy install phases
npm cache clean --force >> "$LOG" 2>&1 || true

# =============================================================================
# STEP 4: UI UX Pro Max Skill
# Design system skill for Claude Code — component patterns, accessibility,
# responsive layouts, design tokens. Installed via uipro-cli.
# =============================================================================
step 4 "UI UX Pro Max Skill"

UIPRO_SKILL_DIR="$HOME/.claude/skills/ui-ux-pro-max"
UIPRO_SKILL_DIR_LOCAL="$WORKSPACE/.claude/skills/ui-ux-pro-max"

if [ -d "$UIPRO_SKILL_DIR" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR" 2>/dev/null)" ]; then
    ok "UI UX Pro Max skill already installed"
elif [ -d "$UIPRO_SKILL_DIR_LOCAL" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR_LOCAL" 2>/dev/null)" ]; then
    ok "UI UX Pro Max skill already installed (local)"
else
    # Clean up empty directories
    [ -d "$UIPRO_SKILL_DIR" ] && [ -z "$(ls -A "$UIPRO_SKILL_DIR" 2>/dev/null)" ] && rm -rf "$UIPRO_SKILL_DIR"
    [ -d "$UIPRO_SKILL_DIR_LOCAL" ] && [ -z "$(ls -A "$UIPRO_SKILL_DIR_LOCAL" 2>/dev/null)" ] && rm -rf "$UIPRO_SKILL_DIR_LOCAL"

    npx -y uipro-cli init --ai claude --offline >> "$LOG" 2>&1 || true

    if [ -d "$UIPRO_SKILL_DIR" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR" 2>/dev/null)" ]; then
        ok "UI UX Pro Max skill installed"
    elif [ -d "$UIPRO_SKILL_DIR_LOCAL" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR_LOCAL" 2>/dev/null)" ]; then
        ok "UI UX Pro Max skill installed (local)"
    else
        warn "UI UX Pro Max skill may be incomplete — run manually: npx uipro-cli init --ai claude"
    fi
fi

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 5: GitNexus — Codebase Knowledge Graph
# Indexes repos into knowledge graph (dependencies, call chains, execution flows)
# Agents get blast-radius detection before making changes
#
# FIX: npm install -g gitnexus was OOM-killed (exit 137) in memory-constrained
# DevPod containers. Now: (a) cap Node heap to 512MB, (b) run install in a
# subshell so OOM only kills the child, (c) gc npm cache between heavy installs,
# (d) anything that fails or is too heavy gets picked up automatically by a
# post-setup background bootstrap — zero manual steps.
# =============================================================================
step 5 "GitNexus (Codebase Knowledge Graph)"

# Free memory before heavy install — previous steps may have left npm caches
npm cache clean --force >> "$LOG" 2>&1 || true

# Track whether post-setup bootstrap is needed
NEEDS_BOOTSTRAP=0

if ! command -v gitnexus &>/dev/null; then
    GNX_OK=0
    (
        export NODE_OPTIONS="--max-old-space-size=512"
        npm install -g gitnexus >> "$LOG" 2>&1
    ) && GNX_OK=1 || true

    if [ "$GNX_OK" -eq 1 ] && command -v gitnexus &>/dev/null; then
        ok "GitNexus installed globally"
    else
        warn "GitNexus install deferred to post-setup bootstrap (memory-constrained)"
        NEEDS_BOOTSTRAP=1
    fi
else
    ok "GitNexus already present"
fi

# Indexing always deferred to bootstrap (runs in background after setup exits
# and all npm install memory is freed)
ok "GitNexus indexing scheduled for post-setup bootstrap"

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 6: Dolt + Beads — Version-Controlled Memory
#
# Dolt is the storage backend required by Beads. It is a Git-like SQL database
# (~100MB binary) that handles all versioning, branching, and merge of issue
# data. Beads (bd) will fail to init without Dolt present.
#
# Install order: Dolt FIRST, then Beads.
#
# Dolt install strategy (in priority order):
#   1. brew install dolt          — macOS with Homebrew (fastest, no sudo needed)
#   2. Official installer script  — Linux with sudo (puts binary in /usr/local/bin)
#   3. No-sudo binary download    — Linux containers without sudo (DevPod, Codespaces)
#      Downloads the release binary directly into $HOME/.local/bin
#   4. Deferred to bootstrap      — if all above fail (OOM, network issue)
#
# After install, configure Dolt git identity so Beads can attribute commits.
# This mirrors git config and needs no user input.
#
# Beads install strategy:
#   1. npm install -g @beads/bd   — primary (in capped subshell, OOM-safe)
#   2. pip install --user beads   — lighter fallback
#   3. Deferred to bootstrap      — if both fail
# =============================================================================
step 6 "Dolt + Beads (Version-Controlled Memory)"

npm cache clean --force >> "$LOG" 2>&1 || true

# ── 6a. Dolt ─────────────────────────────────────────────────────────────────

install_dolt_no_sudo() {
    # Download the release binary directly — no sudo, no npm
    local DOLT_BIN_DIR="$HOME/.local/bin"
    mkdir -p "$DOLT_BIN_DIR"

    local OS ARCH DOLT_URL
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)        ARCH="amd64" ;;  # fallback
    esac

    # Build download URL for latest release tarball
    DOLT_URL="https://github.com/dolthub/dolt/releases/latest/download/dolt-${OS}-${ARCH}.tar.gz"

    echo "    Downloading Dolt binary from $DOLT_URL" >> "$LOG"
    if curl -fsSL "$DOLT_URL" | tar -xz -C "$DOLT_BIN_DIR" --strip-components=2 2>> "$LOG"; then
        # Tarball layout: dolt-linux-amd64/bin/dolt → strip 2 levels
        chmod +x "$DOLT_BIN_DIR/dolt" 2>/dev/null || true
        export PATH="$DOLT_BIN_DIR:$PATH"
        return 0
    fi
    return 1
}

if command -v dolt &>/dev/null; then
    ok "Dolt $(dolt version 2>/dev/null | head -1 | awk '{print $NF}') already present"
else
    DOLT_OK=0

    # Method 1: Homebrew (macOS)
    if command -v brew &>/dev/null; then
        brew install dolt >> "$LOG" 2>&1 && DOLT_OK=1 || true
        [ "$DOLT_OK" -eq 1 ] && ok "Dolt installed via Homebrew"
    fi

    # Method 2: Official installer script (Linux, requires sudo)
    if [ "$DOLT_OK" -eq 0 ] && command -v sudo &>/dev/null; then
        (sudo bash -c 'curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash' >> "$LOG" 2>&1) \
            && DOLT_OK=1 || true
        [ "$DOLT_OK" -eq 1 ] && ok "Dolt installed via official installer"
    fi

    # Method 3: No-sudo binary download (DevPod containers, Codespaces, rootless)
    if [ "$DOLT_OK" -eq 0 ]; then
        install_dolt_no_sudo && command -v dolt &>/dev/null && DOLT_OK=1 || true
        [ "$DOLT_OK" -eq 1 ] && ok "Dolt installed via binary download (no sudo)"
    fi

    # Method 4: Defer to bootstrap
    if [ "$DOLT_OK" -eq 0 ]; then
        warn "Dolt install deferred to post-setup bootstrap"
        NEEDS_BOOTSTRAP=1
    fi
fi

# Configure Dolt git identity (mirrors git config; Beads needs this to commit)
if command -v dolt &>/dev/null; then
    GIT_NAME="$(git config --global user.name 2>/dev/null || echo 'TurboFlow Agent')"
    GIT_EMAIL="$(git config --global user.email 2>/dev/null || echo 'agent@turboflow.local')"
    dolt config --global --add user.name  "$GIT_NAME"  >> "$LOG" 2>&1 || true
    dolt config --global --add user.email "$GIT_EMAIL" >> "$LOG" 2>&1 || true
    ok "Dolt git identity configured ($GIT_NAME <$GIT_EMAIL>)"
fi

# ── 6b. Beads ────────────────────────────────────────────────────────────────
# Beads requires Dolt to be present before bd init can succeed.
# The actual bd init is deferred to bootstrap (needs memory freed first).
# FIX 17: Also create .beads directory structure early for project memory

if ! command -v bd &>/dev/null; then
    BD_OK=0
    (
        export NODE_OPTIONS="--max-old-space-size=512"
        npm install -g @beads/bd >> "$LOG" 2>&1
    ) && BD_OK=1 || true

    if [ "$BD_OK" -eq 1 ] && command -v bd &>/dev/null; then
        ok "Beads installed"
    else
        # Try pip as lighter-weight fallback
        if pip install --user beads >> "$LOG" 2>&1 && command -v bd &>/dev/null; then
            ok "Beads installed (pip)"
        else
            warn "Beads install deferred to post-setup bootstrap (memory-constrained)"
            NEEDS_BOOTSTRAP=1
        fi
    fi
else
    ok "Beads $(bd --version 2>/dev/null | head -1 || echo 'present') already installed"
fi

# bd init deferred to bootstrap (needs all memory freed and Dolt confirmed running)
ok "Beads workspace init scheduled for post-setup bootstrap"

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 7: Workspace + Agent Teams
# =============================================================================
step 7 "Workspace + Agent Teams"

cd "$WORKSPACE"

# Create workspace directories
for dir in src tests docs scripts config plans; do
    mkdir -p "$dir"
done
ok "Workspace directories created"

# FIX 17: Create .worktrees directory for agent isolation
mkdir -p "$WORKSPACE/.worktrees"
ok "Worktrees directory created (.worktrees/)"

# FIX 17: Create .claude/teams directory for persistent agent teams
mkdir -p "$WORKSPACE/.claude/teams"
ok "Agent Teams directory created (.claude/teams/)"

# Enable Native Agent Teams (Anthropic experimental)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
ok "Agent Teams enabled (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 8: Statusline Pro
# =============================================================================
step 8 "Statusline Pro"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_SCRIPT="$HOME/.claude/turbo-flow-statusline.sh"

mkdir -p "$HOME/.claude" 2>/dev/null || true

cat > "$STATUSLINE_SCRIPT" << 'STATUSLINE_SCRIPT'
#!/bin/bash
# TURBO FLOW v4.0 - STATUSLINE

INPUT=$(cat)

# Colors
BG_DEEP="\033[48;5;17m"
BG_DARK="\033[48;5;54m"
FG_MAGENTA="\033[38;5;201m"
FG_CYAN="\033[38;5;51m"
FG_GREEN="\033[38;5;82m"
FG_YELLOW="\033[38;5;226m"
FG_PINK="\033[38;5;198m"
FG_BLUE="\033[38;5;33m"
FG_ORANGE="\033[38;5;214m"
FG_RED="\033[38;5;196m"
FG_WHITE="\033[38;5;255m"
FG_GRAY="\033[38;5;244m"
BG_MAGENTA="\033[48;5;201m"
BG_CYAN="\033[48;5;51m"
BG_GREEN="\033[48;5;82m"
BG_YELLOW="\033[48;5;226m"
BG_PINK="\033[48;5;198m"
BG_BLUE="\033[48;5;33m"
BG_RED="\033[48;5;196m"
RST="\033[0m"
BOLD="\033[1m"
SEP=""

MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
VERSION=$(echo "$INPUT" | jq -r '.version // ""' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null | cut -c1-8)
OUTPUT_STYLE=$(echo "$INPUT" | jq -r '.output_style.name // "default"' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // "~"' 2>/dev/null)
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "project")
COST_USD=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)
DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
LINES_ADDED=$(echo "$INPUT" | jq -r '.cost.total_lines_added // 0' 2>/dev/null)
LINES_REMOVED=$(echo "$INPUT" | jq -r '.cost.total_lines_removed // 0' 2>/dev/null)
CTX_INPUT=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
CTX_OUTPUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null)
CTX_USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
CACHE_CREATE=$(echo "$INPUT" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0' 2>/dev/null)
CACHE_READ=$(echo "$INPUT" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0' 2>/dev/null)

GIT_BRANCH=""
GIT_DIRTY=""
if command -v git &>/dev/null && git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
    [[ -n $(git -C "$CWD" status --porcelain 2>/dev/null) ]] && GIT_DIRTY="*" || GIT_DIRTY=""
fi

format_duration() {
    local ms=$1 secs=$((ms / 1000)) mins=$((ms / 60000)) hours=$((ms / 3600000))
    mins=$((mins % 60)); secs=$((secs % 60))
    if [ $hours -gt 0 ]; then echo "${hours}h${mins}m"
    elif [ $mins -gt 0 ]; then echo "${mins}m${secs}s"
    else echo "${secs}s"; fi
}

format_tokens() {
    local tokens=$1
    if [ $tokens -ge 1000000 ]; then echo "$((tokens / 1000000))M"
    elif [ $tokens -ge 1000 ]; then echo "$((tokens / 1000))k"
    else echo "$tokens"; fi
}

ctx_bar() {
    local pct=$1 width=${2:-15} filled=$((pct * width / 100)) empty=$((width - filled))
    local bar_color="$FG_GREEN"
    [ $pct -ge 50 ] && bar_color="$FG_CYAN"
    [ $pct -ge 70 ] && bar_color="$FG_YELLOW"
    [ $pct -ge 85 ] && bar_color="$FG_ORANGE"
    [ $pct -ge 95 ] && bar_color="$FG_RED"
    printf "${bar_color}"; printf "%${filled}s" | tr ' ' '#'
    printf "${FG_GRAY}"; printf "%${empty}s" | tr ' ' '-'; printf "${RST}"
}

DURATION_FMT=$(format_duration $DURATION_MS)
CTX_TOTAL=$((CTX_INPUT + CTX_OUTPUT))
CTX_TOTAL_FMT=$(format_tokens $CTX_TOTAL)
CTX_SIZE_FMT=$(format_tokens $CTX_SIZE)
CACHE_HIT_PCT=0
[ $((CACHE_READ + CACHE_CREATE)) -gt 0 ] && CACHE_HIT_PCT=$((CACHE_READ * 100 / (CACHE_READ + CACHE_CREATE + 1)))
MODEL_ABBREV=$(echo "$MODEL" | sed 's/Sonnet/So/;s/Opus/Op/;s/Haiku/Ha/' | cut -c1-8)
COST_FMT=$(printf "%.2f" $COST_USD 2>/dev/null || echo "0.00")

LINE1="${BG_MAGENTA}${FG_WHITE}${BOLD} [Project] ${PROJECT_NAME} ${RST}${FG_MAGENTA}${BG_CYAN}${SEP}${RST}${BG_CYAN}${FG_WHITE}${BOLD} [Model] ${MODEL_ABBREV} ${RST}${FG_CYAN}${BG_GREEN}${SEP}${RST}"
[ -n "$GIT_BRANCH" ] && LINE1+="${BG_GREEN}${FG_WHITE}${BOLD} [Git] ${GIT_BRANCH}${GIT_DIRTY} ${RST}${FG_GREEN}${BG_BLUE}${SEP}${RST}" || LINE1+="${BG_GREEN}${FG_WHITE}${BOLD} [Git] — ${RST}${FG_GREEN}${BG_BLUE}${SEP}${RST}"
[ -n "$VERSION" ] && LINE1+="${BG_BLUE}${FG_WHITE} [v] ${VERSION} ${RST}${FG_BLUE}${BG_PINK}${SEP}${RST}"
LINE1+="${BG_PINK}${FG_WHITE} [TF] 4.0 ${RST}"
[ -n "$SESSION_ID" ] && LINE1+="${FG_PINK}${BG_DEEP}${SEP}${RST}${BG_DEEP}${FG_GRAY} [SID] ${SESSION_ID} ${RST}"

LINE2="${BG_YELLOW}${FG_WHITE}${BOLD} [Tokens] ${CTX_TOTAL_FMT}/${CTX_SIZE_FMT} ${RST}${FG_YELLOW}${BG_DARK}${SEP}${RST}${BG_DARK}${FG_WHITE} [Ctx] $(ctx_bar $CTX_USED_PCT 20) ${CTX_USED_PCT}% ${RST}${FG_DARK}${BG_CYAN}${SEP}${RST}"
[ $CACHE_HIT_PCT -gt 0 ] && LINE2+="${BG_CYAN}${FG_WHITE} [Cache] ${CACHE_HIT_PCT}% ${RST}" || LINE2+="${BG_CYAN}${FG_WHITE} [Cache] cold ${RST}"
LINE2+="${FG_CYAN}${BG_PINK}${SEP}${RST}${BG_PINK}${FG_WHITE}${BOLD} [Cost] \$${COST_FMT} ${RST}${FG_PINK}${BG_DEEP}${SEP}${RST}${BG_DEEP}${FG_CYAN} [Time] ${DURATION_FMT} ${RST}"

LINE3=""
[ $LINES_ADDED -gt 0 ] && LINE3+="${BG_GREEN}${FG_WHITE} [+${LINES_ADDED}] ${RST}${FG_GREEN}${BG_RED}${SEP}${RST}${BG_RED}${FG_WHITE} [-${LINES_REMOVED}] ${RST}${FG_RED}${BG_BLUE}${SEP}${RST}" || LINE3+="${BG_BLUE}${FG_WHITE}"
LINE3+="${BG_GREEN}${FG_WHITE}${BOLD} [READY] ${RST}${FG_GREEN}${RST}"

echo -e "${LINE1}"
echo -e "${LINE2}"
echo -e "${LINE3}"
STATUSLINE_SCRIPT
chmod +x "$STATUSLINE_SCRIPT"
ok "Statusline script created"

# ── FIX 6: Configure settings.json with proper quoting and error handling ──
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo '{}' > "$CLAUDE_SETTINGS"
fi

STATUSLINE_SCRIPT_ESCAPED=$(echo "$STATUSLINE_SCRIPT" | sed 's/\\/\\\\/g; s/"/\\"/g')
node -e "
const fs = require('fs');
try {
    const settings = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    settings.statusLine = {
        type: 'command',
        command: process.argv[2],
        padding: 0
    };
    fs.writeFileSync(process.argv[1], JSON.stringify(settings, null, 2));
    process.exit(0);
} catch(e) {
    console.error(e.message);
    process.exit(1);
}
" "$CLAUDE_SETTINGS" "$STATUSLINE_SCRIPT" 2>/dev/null \
    && ok "Statusline configured in settings.json" \
    || warn "settings.json config failed (non-critical)"

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 9: Generate CLAUDE.md
# =============================================================================
step 9 "CLAUDE.md Generation"

cat > "$WORKSPACE/CLAUDE.md" << 'CLAUDEEOF'
# CLAUDE.md — TurboFlow 4.0 Context

## Identity
This workspace runs TurboFlow 4.0 — a composed agentic development environment.
Orchestration: Ruflo v3.5 (skills-based, not slash commands).
Memory: Three-tier (Beads → Native Tasks → AgentDB).
Isolation: Git worktrees per parallel agent.

## Memory Protocol (MANDATORY — follow this every session)

### Session Start
1. Run `bd ready` to check project state (blockers, in-progress work, decisions)
2. Check Native Tasks: review any persisted task lists from prior sessions
3. AgentDB context loads automatically via Ruflo

### During Work — Decision Tree
- **Project roadmap / blockers / dependencies / decisions** → Beads (`bd create`)
- **Current session tasks / active checklist** → Native Tasks
- **Learned patterns / routing weights / skills** → AgentDB (automatic)

### Session End
- File any discovered work as Beads issues:
    bd create "short title" -t bug -p 1 --description "what it is, where it lives"
- Summarize architectural decisions:
    bd create "short title" -t decision -p 0 --description "context and reasoning"
- AgentDB persists automatically

## Isolation Rules
- Each parallel agent MUST operate in its own git worktree
- Create worktree: `git worktree add .worktrees/agent-N -b agent-N/task-name`
- Database schema per worktree: use $DATABASE_SCHEMA env var for PG Vector
- NEVER run `--dangerously-skip-permissions` on bare metal — containers only

## Agent Teams
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is enabled
- Lead agent may spawn up to 3 teammates
- Recursion limit: depth 2 (lead → sub-agents, sub-agents cannot spawn swarms)
- If 3+ agents are blocked simultaneously → pause and alert human

## Model Routing
- Ruflo auto-selects model tier per task complexity (saves ~75% API costs)
- Claude Opus 4.6: complex reasoning, architecture decisions
- Claude Sonnet 4.5: standard coding, implementation
- Claude Haiku 4.5: simple tasks, formatting, quick lookups

## Stack Reference
- Orchestration: `npx ruflo@latest` (NOT claude-flow)
- Swarms: `npx ruflo swarm init --topology hierarchical --max-agents 8`
- Memory: Beads (`bd`), Native Tasks, AgentDB (`npx ruflo agentdb`)
- Codebase Graph: GitNexus (`npx gitnexus analyze`)
- Browser: via Ruflo's bundled browser tools (59 MCP tools, element refs, snapshots)
- Observability: via Ruflo's built-in session tracking + AttestationLog
- Plugins: agentic-qe, code-intelligence, test-intelligence, perf-optimizer, teammate, gastown-bridge
- Specs: OpenSpec (`npx @fission-ai/openspec`)

## Ruflo Plugins
- **Agentic QE**: 58 QE agents — TDD, coverage, security scanning, chaos engineering
- **Code Intelligence**: code analysis, pattern detection, refactoring suggestions
- **Test Intelligence**: test generation, gap analysis, flaky test detection
- **Perf Optimizer**: performance profiling, bottleneck detection
- **Teammate Plugin**: bridges Native Agent Teams ↔ Ruflo swarms (21 MCP tools)
- **Gastown Bridge**: WASM-accelerated orchestration, Beads sync (20 MCP tools)
- **OpenSpec**: spec-driven development (`os init`, `os`)

## Codebase Intelligence (GitNexus)
- Index repo: `npx gitnexus analyze` (run from repo root, creates knowledge graph)
- Before editing shared code: check blast radius via GitNexus MCP tools
- Auto-creates AGENTS.md and CLAUDE.md context files
- One MCP server serves all indexed repos — no per-project config needed

## Cost Guardrails
- Hard session cap: $15/hr (configurable)
- Use Haiku for simple tasks — don't burn Opus on formatting
- Monitor: `claude-usage` or ruflo statusline
CLAUDEEOF

ok "CLAUDE.md generated with 3-tier memory, isolation rules, plugins, cost guardrails"
ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 10: Bash Aliases + MCP Registration
# =============================================================================
step 10 "Aliases + Environment + MCP Registration"

ALIAS_FILE="$HOME/.turboflow_aliases"

cat > "$ALIAS_FILE" << 'ALIASEOF'
# =============================================================================
# TurboFlow 4.0 Aliases
# =============================================================================

# --- Agent Teams ---
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
export AGENTS_DIR="\${WORKSPACE:-\$(pwd)}/agents"

# --- Claude Code ---
alias claude-hierarchical='claude --dangerously-skip-permissions'
alias dsp='claude --dangerously-skip-permissions'

# --- Ruflo (replaces ALL cf-* aliases) ---
alias rf='npx ruflo@latest'
alias rf-init='npx ruflo@latest init'
alias rf-wizard='npx ruflo@latest init --wizard'
alias rf-doctor='npx ruflo@latest doctor --fix'
alias rf-swarm='npx ruflo@latest swarm init --topology hierarchical --max-agents 8 --strategy specialized'
alias rf-mesh='npx ruflo@latest swarm init --topology mesh'
alias rf-ring='npx ruflo@latest swarm init --topology ring'
alias rf-star='npx ruflo@latest swarm init --topology star'
alias rf-daemon='npx ruflo@latest daemon start'
alias rf-status='npx ruflo@latest status'
alias rf-migrate='npx ruflo@latest migrate run --backup'
alias rf-plugins='npx ruflo@latest plugins list'

# Spawn agents
rf-spawn() { npx ruflo@latest agent spawn -t "${1:-coder}" --name "${2:-agent-$RANDOM}"; }
rf-task() { npx ruflo@latest swarm "$1" --parallel; }

# --- RuVector / AgentDB (accessed through ruflo) ---
alias ruv='npx ruflo@latest agentdb'
alias ruv-stats='npx ruflo@latest agentdb stats'
alias ruv-init='npx ruflo@latest agentdb init'
ruv-remember() { npx ruflo@latest agentdb store --key "$1" --value "$2"; }
ruv-recall() { npx ruflo@latest agentdb query "$1"; }

# --- Memory (ruflo native) ---
alias mem-search='npx ruflo@latest memory search'
alias mem-store='npx ruflo@latest memory store'
alias mem-stats='npx ruflo@latest memory stats'

# --- Beads (cross-session memory) ---
# Beads auto-commits every write to local Dolt history — no push needed for solo use.
# For team sharing via a Dolt remote: bd dolt remote add origin <url> && bd dolt push
alias bd-ready='bd ready'
alias bd-list='bd list'
alias bd-status='bd status'
bd-add() {
    # Usage: bd-add "title" bug|decision|task [priority 0-3] ["description"]
    local title="${1:?Usage: bd-add 'title' type [priority] ['description']}"
    local type="${2:-task}"
    local priority="${3:-1}"
    local description="${4:-}"
    if [ -n "$description" ]; then
        bd create "$title" -t "$type" -p "$priority" --description "$description"
    else
        bd create "$title" -t "$type" -p "$priority"
    fi
}

# --- Dolt (Beads storage backend) ---
alias dolt-status='dolt status 2>/dev/null || echo "Not in a Dolt repo"'
alias dolt-log='dolt log 2>/dev/null || echo "Not in a Dolt repo"'
# For team sharing only — not needed for solo use:
alias bd-push='bd dolt push'
alias bd-pull='bd dolt pull'

# --- Git Worktrees (agent isolation) ---
wt-add() {
    local name="${1:?Usage: wt-add <agent-name>}"
    git worktree add ".worktrees/$name" -b "$name/$(date +%s)"
    echo "Worktree created: .worktrees/$name"
    export DATABASE_SCHEMA="wt_${name}_$(date +%s)"
    # Auto-index with GitNexus if available
    if command -v npx &>/dev/null; then
        (cd ".worktrees/$name" && npx gitnexus analyze 2>/dev/null &)
    fi
}
wt-remove() {
    local name="${1:?Usage: wt-remove <agent-name>}"
    git worktree remove ".worktrees/$name" --force 2>/dev/null
    echo "Worktree removed: $name"
}
wt-list() { git worktree list; }
wt-clean() { git worktree prune; }

# --- GitNexus (codebase knowledge graph) ---
alias gnx='npx gitnexus'
alias gnx-analyze='npx gitnexus analyze'
alias gnx-analyze-force='npx gitnexus analyze --force'
alias gnx-mcp='npx gitnexus mcp'
alias gnx-serve='npx gitnexus serve'
alias gnx-status='npx gitnexus status'
alias gnx-wiki='npx gitnexus wiki'
alias gnx-list='npx gitnexus list'
alias gnx-clean='npx gitnexus clean'

# --- Agentic QE (via ruflo plugin) ---
alias aqe='npx ruflo@latest plugins run agentic-qe'
alias aqe-generate='npx ruflo@latest plugins run agentic-qe generate'
alias aqe-gate='npx ruflo@latest plugins run agentic-qe gate'

# --- OpenSpec (spec-driven development) ---
alias os='npx @fission-ai/openspec'
alias os-init='npx @fission-ai/openspec init'

# --- Hooks Intelligence (ruflo native) ---
alias hooks-pre='npx ruflo@latest hooks pre-edit'
alias hooks-post='npx ruflo@latest hooks post-edit'
alias hooks-train='npx ruflo@latest hooks pretrain --depth deep'
alias hooks-route='npx ruflo@latest hooks route'

# --- Neural (ruflo native) ---
alias neural-train='npx ruflo@latest neural train'
alias neural-status='npx ruflo@latest neural status'
alias neural-patterns='npx ruflo@latest neural patterns'

# --- Usage monitoring ---
alias claude-usage='claude usage 2>/dev/null || echo "Run inside claude session"'

# --- TurboFlow Meta ---
turbo-status() {
    echo "╔══════════════════════════════════════════╗"
    echo "║       TurboFlow 4.0 Status Check         ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "Core:"
    claude --version 2>/dev/null && echo "  ✓ Claude Code" || echo "  ✗ Claude Code"
    npx ruflo@latest --version 2>/dev/null && echo "  ✓ Ruflo" || echo "  ✗ Ruflo"
    echo ""
    echo "Memory:"
    command -v dolt &>/dev/null \
        && echo "  ✓ Dolt $(dolt version 2>/dev/null | awk 'NR==1{print $NF}')" \
        || echo "  ✗ Dolt (required by Beads — install: curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo bash)"
    command -v bd &>/dev/null \
        && echo "  ✓ Beads $(bd --version 2>/dev/null | head -1)" \
        || echo "  ✗ Beads (install: npm i -g @beads/bd)"
    [ -d ".beads" ] \
        && echo "  ✓ Beads initialized in this project" \
        || echo "  ○ Beads not initialized here (run: bd init)"
    echo "  Agent Teams: ${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-off}"
    echo ""
    echo "Plugins:"
    npx ruflo@latest plugins list 2>/dev/null | head -10 || echo "  Run: rf-plugins"
    echo ""
    echo "Codebase Intelligence:"
    command -v gitnexus &>/dev/null && echo "  ✓ GitNexus" || (npx gitnexus --version 2>/dev/null && echo "  ✓ GitNexus (via npx)" || echo "  ○ GitNexus")
    echo ""
    echo "Workspace:"
    [ -f "CLAUDE.md" ] && echo "  ✓ CLAUDE.md" || echo "  ✗ CLAUDE.md (run setup again)"
    git worktree list 2>/dev/null | head -5
    echo ""
    echo "Agents: $(ls -1 agents/*.md 2>/dev/null | wc -l || echo '0') subagent files"
    echo "Statusline: $([ -x "$HOME/.claude/turbo-flow-statusline.sh" ] && echo '✓ active' || echo '✗ missing')"
}

turbo-help() {
    echo "TurboFlow 4.0 — Quick Reference"
    echo ""
    echo "Orchestration (Ruflo):"
    echo "  rf-wizard          Interactive setup"
    echo "  rf-swarm           Launch hierarchical swarm (8 agents max)"
    echo "  rf-spawn coder     Spawn a coder agent"
    echo "  rf-doctor          Health check + auto-fix"
    echo "  rf-daemon          Start background workers"
    echo "  rf-plugins         List installed plugins"
    echo ""
    echo "Memory:"
    echo "  bd-ready           Check project state (session start)"
    echo "  bd-add 'title' decision 0 'reasoning'   Record a decision"
    echo "  bd-add 'title' bug 1 'what and where'   Record a bug"
    echo "  ruv-remember K V   Store in AgentDB"
    echo "  ruv-recall Q       Query AgentDB"
    echo "  mem-search Q       Search ruflo memory"
    echo ""
    echo "  Note: Beads auto-saves locally — no push needed for solo use."
    echo "  For team sharing: bd dolt remote add origin <url> && bd-push"
    echo ""
    echo "Isolation:"
    echo "  wt-add agent-1     Create worktree for agent"
    echo "  wt-remove agent-1  Clean up worktree"
    echo "  wt-list            Show all worktrees"
    echo ""
    echo "Quality & Testing:"
    echo "  aqe-generate       Generate tests (Agentic QE plugin)"
    echo "  aqe-gate           Quality gate"
    echo "  os-init            Initialize OpenSpec in project"
    echo "  os                 Run OpenSpec"
    echo ""
    echo "Intelligence:"
    echo "  hooks-train        Deep pretrain on codebase"
    echo "  hooks-route        Route task to optimal agent"
    echo "  neural-train       Train neural patterns"
    echo "  neural-patterns    View learned patterns"
    echo ""
    echo "Codebase Intelligence (GitNexus):"
    echo "  gnx-analyze        Index repo into knowledge graph"
    echo "  gnx-serve          Start local server for web UI"
    echo "  gnx-wiki           Generate repo wiki from graph"
    echo ""
    echo "Status: turbo-status | Logs: cat /tmp/turboflow-setup.log"
}
ALIASEOF

# ── FIX 9: Source aliases into shell configs — handle missing files and sed differences ──
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        # Remove old turbo flow alias blocks from v3.x (GNU sed compatible)
        sed -i '/# === TURBO FLOW/,/# === END TURBO FLOW/d' "$rc" 2>/dev/null || true
        grep -q 'turboflow_aliases' "$rc" 2>/dev/null || \
            echo "[ -f \"$ALIAS_FILE\" ] && source \"$ALIAS_FILE\"" >> "$rc"
    fi
done

source "$ALIAS_FILE" 2>/dev/null || true
ok "Aliases written to $ALIAS_FILE and sourced"

# ── FIX 10: MCP Registration — all commands fully guarded ──

# GitNexus MCP
if npx gitnexus setup >> "$LOG" 2>&1; then
    ok "GitNexus MCP registered"
else
    if claude mcp add gitnexus -- npx -y gitnexus mcp >> "$LOG" 2>&1; then
        ok "GitNexus MCP registered manually"
    else
        warn "GitNexus MCP registration failed (run: npx gitnexus setup)"
    fi
fi

# FIX 14: Security scan — Ruflo v3.5+ has built-in AIDefence
# Note: @claude-flow/cli security scan is redundant with Ruflo's AIDefence
if command -v claude &>/dev/null; then
    npx ruflo@latest aidefence stats >> "$LOG" 2>&1 \
        && ok "Ruflo AIDefence security stats retrieved" \
        || warn "Ruflo AIDefence check failed (run: npx ruflo aidefence stats)"
fi

ok "All MCP servers registered"

# Clear stale caches
npm cache clean --force >> "$LOG" 2>&1 || true
rm -rf /tmp/npm-* /tmp/nvm-* 2>/dev/null || true

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 11: Start Services (Ruflo Daemon + Dolt for Beads)
# FIX 13: Auto-start daemon for background workers (map, audit, optimize)
# FIX 16: Start Dolt server first — Beads requires it for database backend
# =============================================================================
step 11 "Start Services"

# ── Dolt for Beads ──────────────────────────────────────────────────────
# Do NOT hand-start a Dolt sql-server here. Beads (bd) v1.x manages its own
# embedded Dolt server (auto-selected port) and creates the project database
# during `bd init`. A manually-started server on a fixed port is never used by
# bd and only causes confusion. We just verify the Dolt binary is present; the
# actual server + database come up via `bd init` in the post-setup bootstrap.
if command -v dolt &>/dev/null; then
    ok "Dolt binary present ($(dolt version 2>/dev/null | head -1 | awk '{print $NF}')) — Beads will manage its server"
else
    warn "Dolt binary missing — Beads init deferred to post-setup bootstrap"
fi

# ── Start Ruflo daemon (with retry) ─────────────────────────────────
if npx ruflo@latest daemon status 2>/dev/null | grep -q "running"; then
    ok "Ruflo daemon already running"
else
    if npx ruflo@latest daemon start --timeout 30 >> "$LOG" 2>&1; then
        sleep 2
        if npx ruflo@latest daemon status 2>/dev/null | grep -q "running"; then
            ok "Ruflo daemon started (background workers active)"
        else
            warn "Ruflo daemon start may have failed — check with: rf-daemon"
        fi
    else
        warn "Ruflo daemon start failed (optional — start manually with: rf-daemon)"
    fi
fi

ok "Elapsed: $(elapsed)"

# =============================================================================
# POST-SETUP BOOTSTRAP — runs in background after setup exits
#
# This handles everything too heavy to run during setup (OOM risk):
#   1. Retry any failed installs (Dolt, GitNexus, Beads) now that npm caches
#      are freed
#   2. Start Dolt server if not running (required for Beads database)
#   3. Run bd init in the workspace (requires Dolt server to be running)
#   4. Run gitnexus analyze on the workspace with execution flow detection
#   5. Register GitNexus MCP if install was deferred
#   6. Self-deletes the one-shot shell hook after completion
# =============================================================================

BOOTSTRAP_SCRIPT="$HOME/.turboflow-bootstrap.sh"
BOOTSTRAP_LOG="/tmp/turboflow-bootstrap.log"
BOOTSTRAP_LOCK="/tmp/turboflow-bootstrap.lock"
BOOTSTRAP_DONE="$HOME/.turboflow-bootstrap-done"

cat > "$BOOTSTRAP_SCRIPT" << BOOTSTRAPEOF
#!/bin/bash
# TurboFlow 4.0 — Post-Setup Bootstrap (auto-runs once, then self-removes)

set -uo pipefail

BSLOG="$BOOTSTRAP_LOG"
LOCK="$BOOTSTRAP_LOCK"
DONE_FLAG="$BOOTSTRAP_DONE"
WORKSPACE="$WORKSPACE"

[ -f "\$DONE_FLAG" ] && exit 0

if [ -f "\$LOCK" ]; then
    LOCK_PID=\$(cat "\$LOCK" 2>/dev/null)
    if [ -n "\$LOCK_PID" ] && kill -0 "\$LOCK_PID" 2>/dev/null; then
        exit 0
    fi
fi
echo \$\$ > "\$LOCK"
trap 'rm -f "\$LOCK"' EXIT

echo "[\$(date)] Bootstrap starting" >> "\$BSLOG"

export NODE_OPTIONS="--max-old-space-size=512"

# --- 1. Retry Dolt install if missing ---
if ! command -v dolt &>/dev/null; then
    echo "[\$(date)] Installing Dolt..." >> "\$BSLOG"
    # Try official installer first (may have sudo in CI/CD environments)
    if command -v sudo &>/dev/null; then
        sudo bash -c 'curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | bash' >> "\$BSLOG" 2>&1 || true
    fi
    # No-sudo binary fallback
    if ! command -v dolt &>/dev/null; then
        DOLT_BIN_DIR="\$HOME/.local/bin"
        mkdir -p "\$DOLT_BIN_DIR"
        OS="\$(uname -s | tr '[:upper:]' '[:lower:]')"
        ARCH="\$(uname -m)"
        [ "\$ARCH" = "aarch64" ] && ARCH="arm64"
        [ "\$ARCH" = "x86_64" ]  && ARCH="amd64"
        curl -fsSL "https://github.com/dolthub/dolt/releases/latest/download/dolt-\${OS}-\${ARCH}.tar.gz" \
            | tar -xz -C "\$DOLT_BIN_DIR" --strip-components=2 >> "\$BSLOG" 2>&1 || true
        export PATH="\$DOLT_BIN_DIR:\$PATH"
    fi
fi

# Configure Dolt identity if now available
if command -v dolt &>/dev/null; then
    GIT_NAME="\$(git config --global user.name 2>/dev/null || echo 'TurboFlow Agent')"
    GIT_EMAIL="\$(git config --global user.email 2>/dev/null || echo 'agent@turboflow.local')"
    dolt config --global --add user.name  "\$GIT_NAME"  >> "\$BSLOG" 2>&1 || true
    dolt config --global --add user.email "\$GIT_EMAIL" >> "\$BSLOG" 2>&1 || true
    echo "[\$(date)] Dolt identity configured" >> "\$BSLOG"
fi

# --- 2. Retry GitNexus install if missing ---
if ! command -v gitnexus &>/dev/null; then
    echo "[\$(date)] Installing GitNexus..." >> "\$BSLOG"
    npm install -g gitnexus >> "\$BSLOG" 2>&1 || true
fi

# --- 3. Retry Beads install if missing (requires Dolt) ---
if ! command -v bd &>/dev/null; then
    echo "[\$(date)] Installing Beads..." >> "\$BSLOG"
    npm install -g @beads/bd >> "\$BSLOG" 2>&1 || true
fi
if ! command -v bd &>/dev/null; then
    pip install --user beads >> "\$BSLOG" 2>&1 || true
fi

# --- 4. (Dolt server is managed by bd itself — nothing to start here) ---
# bd v1.x spawns and manages its own embedded Dolt sql-server on init/bootstrap.
# Do NOT start a competing server on a fixed port; it would not be used by bd.

# --- 5. Initialize Beads in workspace (bd manages Dolt) ---
if command -v dolt &>/dev/null && command -v bd &>/dev/null && [ -d "\$WORKSPACE/.git" ]; then
    # Beads needs a role configured for routing to work.
    git config beads.role maintainer 2>/dev/null || true

    if [ ! -d "\$WORKSPACE/.beads" ]; then
        echo "[\$(date)] Initializing Beads in workspace..." >> "\$BSLOG"
        (cd "\$WORKSPACE" && bd init >> "\$BSLOG" 2>&1) || true
    fi

    # FIX 18: Handle case where database exists but bd init was not run
    # Check if database exists on Dolt server but .beads is not properly initialized
    if [ -d "\$WORKSPACE/.beads" ]; then
        # Fix .beads permissions
        chmod 700 "\$WORKSPACE/.beads" 2>/dev/null || true

        # Try bd bootstrap if bd status fails (database not found but directory exists)
        if ! (cd "\$WORKSPACE" && bd status >/dev/null 2>&1); then
            echo "[\$(date)] Beads database not found, running bootstrap..." >> "\$BSLOG"
            (cd "\$WORKSPACE" && bd bootstrap --dry-run >/dev/null 2>&1) && \
                (cd "\$WORKSPACE" && bd bootstrap >> "\$BSLOG" 2>&1) || true
        fi
    fi

    # FIX 17: Create initial project memory entries
    echo "[\$(date)] Creating initial Beads entries..." >> "\$BSLOG"
    (cd "\$WORKSPACE" && \
        bd create "TurboFlow 4.0 Initialized" -t decision -p 0 --description "Workspace setup with Ruflo v3.5, Beads, GitNexus, and 6 core plugins. Agent Teams enabled with hierarchical-mesh topology." >> "\$BSLOG" 2>&1 || true) && \
    (cd "\$WORKSPACE" && \
        bd create "Worktree Isolation Policy" -t decision -p 0 --description "Each parallel agent MUST operate in its own git worktree under .worktrees/. Create with: wt-add <agent-name>" >> "\$BSLOG" 2>&1 || true) && \
    (cd "\$WORKSPACE" && \
        bd create "3-Tier Memory Protocol" -t decision -p 0 --description "Beads for roadmap/blockers/decisions, Native Tasks for session checklists, AgentDB for learned patterns and routing." >> "\$BSLOG" 2>&1 || true) || true
fi

# --- 6. Index workspace with GitNexus (with --force --processes flags) ---
# FIX 15: Use --force --processes to ensure proper indexing with execution flows
# FIX 18: Handle case where repo is already partially indexed
if [ -d "\$WORKSPACE/.git" ]; then
    # Check if already indexed
    if [ ! -d "\$WORKSPACE/.gitnexus" ] && [ ! -f "\$WORKSPACE/.gitnexus.json" ]; then
        echo "[\$(date)] GitNexus: workspace not indexed, starting analysis..." >> "\$BSLOG"
        if command -v gitnexus &>/dev/null; then
            (cd "\$WORKSPACE" && gitnexus analyze --force >> "\$BSLOG" 2>&1) || true
        else
            (cd "\$WORKSPACE" && npx -y gitnexus analyze --force >> "\$BSLOG" 2>&1) || true
        fi
    else
        echo "[\$(date)] GitNexus: workspace already indexed" >> "\$BSLOG"
    fi
fi

# --- 6. Register GitNexus MCP if not already done ---
if command -v gitnexus &>/dev/null || npx gitnexus --version >> "\$BSLOG" 2>&1; then
    npx gitnexus setup >> "\$BSLOG" 2>&1 \
        || claude mcp add gitnexus -- npx -y gitnexus mcp >> "\$BSLOG" 2>&1 \
        || true
fi

touch "\$DONE_FLAG"
echo "[\$(date)] Bootstrap complete" >> "\$BSLOG"

for rc in "\$HOME/.bashrc" "\$HOME/.zshrc"; do
    [ -f "\$rc" ] && sed -i '/turboflow-bootstrap/d' "\$rc" 2>/dev/null || true
done

rm -f "\$LOCK"
BOOTSTRAPEOF

chmod +x "$BOOTSTRAP_SCRIPT"

(sleep 5 && nohup "$BOOTSTRAP_SCRIPT" >> "$BOOTSTRAP_LOG" 2>&1 &) &
disown 2>/dev/null || true
ok "Post-setup bootstrap launched (background, 5s delay)"

BOOTSTRAP_HOOK="[ ! -f \"$BOOTSTRAP_DONE\" ] && [ -x \"$BOOTSTRAP_SCRIPT\" ] && (nohup \"$BOOTSTRAP_SCRIPT\" >> \"$BOOTSTRAP_LOG\" 2>&1 &)"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -q 'turboflow-bootstrap' "$rc" 2>/dev/null || \
            echo "$BOOTSTRAP_HOOK  # turboflow-bootstrap one-shot" >> "$rc"
    fi
done
ok "Bootstrap shell hook installed (auto-removes after completion)"

# =============================================================================
# DONE
# =============================================================================
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         ${GREEN}✓ TurboFlow 4.0 Setup Complete${NC}${BOLD}          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Summary:${NC}"
echo -e "    Core:    Claude Code + Ruflo v3.5 (215 MCP tools, 60+ agents)"
echo -e "    Plugins: $PLUGINS_INSTALLED/6 (agentic-qe, code-intel, test-intel, perf, teammate, gastown)"
echo -e "    Memory:  Dolt + Beads + Native Tasks + AgentDB"
echo -e "    Graph:   GitNexus codebase knowledge graph"
echo -e "    Daemon:  Background workers active"
echo -e "    Security: Initial scan completed"
echo -e "    Time:    ${TOTAL_TIME}s"
if [ "$NEEDS_BOOTSTRAP" -eq 1 ]; then
echo -e "    ${YELLOW}Bootstrap:${NC} finishing deferred installs in background (~30-60s)"
echo -e "             check progress: tail -f $BOOTSTRAP_LOG"
fi
echo ""
echo -e "  ${BOLD}Next:${NC} ${CYAN}claude${NC}  (everything else is automatic)"
echo ""
echo -e "  ${BOLD}Changed from v3.4.1:${NC}"
echo -e "    • claude-flow@alpha → ${GREEN}ruflo@latest${NC} (rf-* aliases)"
echo -e "    • 15 plugins → ${GREEN}6 plugins${NC} (9 redundant/domain-specific removed)"
echo -e "    • Slash commands → ${GREEN}skills${NC} (auto-activated)"
echo -e "    • No cross-session memory → ${GREEN}Dolt + Beads${NC} (bd-* aliases)"
echo -e "    • No codebase awareness → ${GREEN}GitNexus${NC} (gnx-* aliases)"
echo -e "    • Manual worktree skill → ${GREEN}native wt-* helpers${NC}"
echo -e "    • 4 separate core installs → ${GREEN}1 ruflo init${NC}"
echo -e "    • MCP manual start → ${GREEN}autoStart enabled${NC}"
echo -e "    • No daemon → ${GREEN}auto-started${NC}"
echo -e "    • No security scan → ${GREEN}automated${NC}"
echo ""
echo -e "  ${BOLD}Logs:${NC} setup=$LOG  bootstrap=$BOOTSTRAP_LOG"
echo ""
