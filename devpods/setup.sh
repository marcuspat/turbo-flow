#!/usr/bin/env bash
# =============================================================================
# TurboFlow 4.0 Setup Script (FIXED)
# Replaces: .devcontainer/setup.sh from v3.4.1
#
# FIXES applied:
#   FIX 1: Ruflo init now handles "already initialized" gracefully (was crashing
#          the entire script because non-zero exit + set -e)
#   FIX 2: All claude mcp commands wrapped to never fail under set -e
#   FIX 3: npx ruflo doctor -- removed --fix flag (interactive prompt hang), added timeout 60
#   FIX 4: Plugin install arithmetic fixed (PLUGINS_INSTALLED increment)
#   FIX 5: Step numbering corrected (was two "STEP 5"s, steps 6-10 misnumbered)
#   FIX 6: node -e for settings.json uses proper quoting
#   FIX 7: All optional tool installs (gitnexus, beads, openspec) fully guarded
#   FIX 8: bd init / gitnexus analyze in subshells with || true
#   FIX 9: sed -i compatibility (GNU vs BSD) handled
#   FIX 10: MCP registration section fully guarded
#   FIX 11: Removed --wizard flag from ruflo init (caused hang on non-TTY/stdin)
#   FIX 12: Added timeout 30 to claude mcp add to prevent auth-prompt hang
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

step() { echo -e "\n${CYAN}━━━ [$1/10] $2 ━━━${NC}"; }
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

ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 2: Claude Code + Ruflo v3.5
# Ruflo v3.5 bundles: AgentDB v3, RuVector WASM, SONA, 215 MCP tools,
# 60+ agents, skills system, 3-tier model routing, browser automation (59 MCP
# browser tools), observability, gating, multi-model routing
# This single install replaces: claude-flow@alpha, @ruvector/cli, @ruvector/sona,
# @claude-flow/browser, agentic-flow, security-analyzer, ui-ux-pro-max
# =============================================================================
step 2 "Claude Code + Ruflo v3.5"

# Claude Code
if ! command -v claude &>/dev/null; then
    npm install -g @anthropic-ai/claude-code >> "$LOG" 2>&1 || true
    if command -v claude &>/dev/null; then
        ok "Claude Code installed"
    else
        # Fallback to official installer
        curl -fsSL https://claude.ai/install.sh 2>/dev/null | sh 2>&1 || true
        export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"
        if command -v claude &>/dev/null; then
            ok "Claude Code installed via official installer"
        else
            fail "Claude Code install failed — install manually: npm i -g @anthropic-ai/claude-code"
        fi
    fi
else
    ok "Claude Code $(claude --version 2>/dev/null | head -1 || echo 'present')"
fi

# ── FIX 1 + FIX 11: Ruflo init — handle "already initialized" without crashing ──
# npx ruflo@latest init returns non-zero when already initialized.
# With set -e, this killed the entire script. Now we check the exit code
# and treat "already initialized" as success.
# --wizard flag removed: caused indefinite hang on non-TTY/no-stdin environments.
RUFLO_INIT_OUTPUT=""
RUFLO_INIT_RC=0
RUFLO_INIT_OUTPUT=$(npx ruflo@latest init 2>&1) || RUFLO_INIT_RC=$?

if [ $RUFLO_INIT_RC -eq 0 ]; then
    ok "Ruflo v3.5 initialized (includes RuVector, AgentDB, SONA, skills, browser, observability)"
elif echo "$RUFLO_INIT_OUTPUT" | grep -qi "already initialized\|already exists\|Found:"; then
    ok "Ruflo v3.5 already initialized (skipped re-init)"
else
    # Actually failed — try without --wizard
    RUFLO_INIT_OUTPUT2=""
    RUFLO_INIT_RC2=0
    RUFLO_INIT_OUTPUT2=$(npx ruflo@latest init 2>&1) || RUFLO_INIT_RC2=$?
    if [ $RUFLO_INIT_RC2 -eq 0 ]; then
        ok "Ruflo v3.5 initialized (no wizard)"
    elif echo "$RUFLO_INIT_OUTPUT2" | grep -qi "already initialized\|already exists\|Found:"; then
        ok "Ruflo v3.5 already initialized"
    else
        warn "Ruflo init returned code $RUFLO_INIT_RC2 — continuing (may need manual: npx ruflo@latest init --force)"
        echo "$RUFLO_INIT_OUTPUT2" >> "$LOG" 2>&1
    fi
fi

# ── FIX 2 + FIX 12: MCP registration — fully guarded, timeout added to prevent
# auth-prompt hang on claude mcp add ──
claude mcp remove claude-flow 2>/dev/null || true
timeout 30 claude mcp add ruflo -- npx -y ruflo@latest 2>/dev/null \
    && ok "Ruflo MCP server registered" \
    || warn "Ruflo MCP registration skipped (configure manually if needed)"

# ── FIX 3: Doctor check — guarded ──
timeout 60 npx ruflo doctor >> "$LOG" 2>&1 \
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
# STEP 6: Beads — Cross-Session Project Memory (NEW in 4.0)
# Agents remember across sessions via git-native Dolt SQL database.
# Beads requires Dolt (https://dolthub.com) as its database backend.
# Repo: https://github.com/steveyegge/beads
# Install: go install github.com/steveyegge/beads/cmd/bd@latest
# FIX: Same OOM protection as GitNexus — subshell + capped heap.
# =============================================================================
step 6 "Beads (Cross-Session Memory)"

# 6a: Install Dolt (Beads database backend) if not present
if ! command -v dolt &>/dev/null; then
    (
        DOLT_ARCH=$(uname -m)
        case "$DOLT_ARCH" in
            x86_64|amd64) DOLT_ARCH="amd64" ;;
            aarch64|arm64) DOLT_ARCH="arm64" ;;
            *) DOLT_ARCH="amd64" ;;
        esac
        curl -L "https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-${DOLT_ARCH}.tar.gz" \
            -o /tmp/dolt.tar.gz 2>/dev/null
        sudo tar -xzf /tmp/dolt.tar.gz -C /usr/local/bin/ 2>/dev/null
        # The tar extracts to a directory structure — find and move the actual binary
        if [ -d "/usr/local/bin/dolt/bin" ]; then
            sudo cp /usr/local/bin/dolt/bin/dolt /usr/local/bin/dolt-bin 2>/dev/null
            sudo rm -rf /usr/local/bin/dolt 2>/dev/null
            sudo mv /usr/local/bin/dolt-bin /usr/local/bin/dolt 2>/dev/null
        fi
        sudo chmod +x /usr/local/bin/dolt 2>/dev/null
        rm -f /tmp/dolt.tar.gz
    ) || true
    if command -v dolt &>/dev/null; then
        ok "Dolt $(dolt version 2>/dev/null) installed (Beads database backend)"
    else
        warn "Dolt not installed — Beads requires Dolt. Install manually from https://docs.dolthub.com"
    fi
else
    ok "Dolt $(dolt version 2>/dev/null) already present"
fi

if ! command -v bd &>/dev/null; then
    BD_OK=0

    # First try Go install (primary method from steveyegge/beads repo)
    if command -v go &>/dev/null; then
        (
            export NODE_OPTIONS="--max-old-space-size=512"
            go install github.com/steveyegge/beads/cmd/bd@latest >> "$LOG" 2>&1
        ) && BD_OK=1 || true

        if [ "$BD_OK" -eq 1 ] && command -v bd &>/dev/null; then
            ok "Beads installed via Go"
        fi
    fi

    # Fallback: Try npm package if Go install failed or Go not available
    # Note: npm package name is @beads/bd, NOT beads-cli
    if [ "$BD_OK" -eq 0 ]; then
        (
            export NODE_OPTIONS="--max-old-space-size=512"
            npm install -g @beads/bd >> "$LOG" 2>&1
        ) && BD_OK=1 || true

        if [ "$BD_OK" -eq 1 ] && command -v bd &>/dev/null; then
            ok "Beads installed via npm"
        fi
    fi

    # Final fallback: Download binary from GitHub releases
    if [ "$BD_OK" -eq 0 ]; then
        BD_VERSION="v1.0.8"
        BD_ARCH=$(uname -m)
        BD_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

        case "$BD_ARCH" in
            x86_64|amd64) BD_ARCH="amd64" ;;
            arm64|aarch64) BD_ARCH="arm64" ;;
            *) BD_ARCH="amd64" ;;  # fallback
        esac

        case "$BD_OS" in
            darwin) BD_OS="darwin" ;;
            linux) BD_OS="linux" ;;
            *) BD_OS="linux" ;;  # fallback
        esac

        BD_URL="https://github.com/steveyegge/beads/releases/download/${BD_VERSION}/bd-${BD_OS}-${BD_ARCH}.tar.gz"

        (
            curl -fsSL "$BD_URL" | tar -xzf - -C "$HOME/.local/bin" >> "$LOG" 2>&1
            chmod +x "$HOME/.local/bin/bd" 2>/dev/null
        ) && BD_OK=1 || true

        if [ "$BD_OK" -eq 1 ] && command -v bd &>/dev/null; then
            ok "Beads installed via binary download"
        else
            warn "Beads install deferred to post-setup bootstrap"
            NEEDS_BOOTSTRAP=1
        fi
    fi
else
    ok "Beads already present"
fi

# Beads init deferred to bootstrap (needs all memory freed first)
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
- **Project roadmap / blockers / dependencies / decisions** → `bd create` (Beads)
- **Current session tasks / active checklist** → Native Tasks
- **Learned patterns / routing weights / skills** → AgentDB (automatic)

### Session End
- File any discovered work as Beads issues: `bd create "description" -t issue`
- Summarize architectural decisions in Beads: `bd create "description" -t decision`
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

# --- Memory (ruflo native) ---
# Use 'ruflo memory' for persistent storage (replaces agentdb)
alias mem='npx ruflo@latest memory'
alias mem-search='npx ruflo@latest memory search'
alias mem-store='npx ruflo@latest memory store'
alias mem-stats='npx ruflo@latest memory stats'
mem-remember() { npx ruflo@latest memory store --key "$1" --value "$2"; }
mem-recall() { npx ruflo@latest memory search "$1"; }

# --- Beads (cross-session memory) ---
# Note: 'bd' is installed directly, no alias needed
alias bd-ready='bd ready'
alias bd-add='bd add'
alias bd-list='bd list'
alias bd-status='bd status'

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

# --- Agentic QE (via ruflo MCP tools) ---
# Access 58 QE agents through MCP tool calls, not 'plugins run'
# Examples:
#   npx ruflo@latest mcp call aqe/generate-tests --targetPath ./src --testType unit
#   npx ruflo@latest mcp call aqe/security-scan --targetPath ./src --scanType sast
#   npx ruflo@latest mcp call aqe/evaluate-quality-gate
aqe() {
    echo "Agentic QE is accessed via MCP tools. Examples:"
    echo "  npx ruflo@latest mcp call aqe/generate-tests --targetPath ./src"
    echo "  npx ruflo@latest mcp call aqe/security-scan --targetPath ./src"
    echo "  npx ruflo@latest mcp call aqe/predict-defects --targetPath ./src"
}
aqe-generate() {
    npx ruflo@latest mcp call aqe/generate-tests "$@"
}
aqe-gate() {
    npx ruflo@latest mcp call aqe/evaluate-quality-gate "$@"
}

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
    bd --version 2>/dev/null && echo "  ✓ Beads" || echo "  ✗ Beads (install: go install github.com/steveyegge/beads/cmd/bd@latest)"
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
    [ -d ".beads" ] && echo "  ✓ Beads initialized" || echo "  ○ Beads not initialized (run: bd init)"
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
    echo "  bd-add             Record issue/decision/blocker"
    echo "  mem-store K V      Store in ruflo memory"
    echo "  mem-search Q       Search ruflo memory"
    echo "  mem-stats          View memory statistics"
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

# ── FIX 10 + FIX 12: MCP Registration — all commands fully guarded, timeout added ──

# GitNexus MCP
if npx gitnexus setup >> "$LOG" 2>&1; then
    ok "GitNexus MCP registered"
else
    if timeout 30 claude mcp add gitnexus -- npx -y gitnexus mcp >> "$LOG" 2>&1; then
        ok "GitNexus MCP registered manually"
    else
        warn "GitNexus MCP registration failed (run: npx gitnexus setup)"
    fi
fi

ok "All MCP servers registered"

# Clear stale caches
npm cache clean --force >> "$LOG" 2>&1 || true
rm -rf /tmp/npm-* /tmp/nvm-* 2>/dev/null || true

ok "Elapsed: $(elapsed)"

# =============================================================================
# POST-SETUP BOOTSTRAP — runs in background after setup exits
#
# This handles everything too heavy to run during setup (OOM risk):
#   1. Retry any failed installs (GitNexus, Beads) now that npm caches are freed
#   2. Run gitnexus analyze on the workspace
#   3. Run bd init in the workspace
#   4. Register GitNexus MCP if install was deferred
#   5. Self-deletes the one-shot shell hook after completion
#
# Two triggers ensure it runs automatically:
#   A. Immediately: nohup background process launched at end of setup
#   B. Shell login fallback: one-shot hook in .bashrc/.zshrc (in case A is
#      killed when the DevPod container restarts after setup)
# =============================================================================

BOOTSTRAP_SCRIPT="$HOME/.turboflow-bootstrap.sh"
BOOTSTRAP_LOG="/tmp/turboflow-bootstrap.log"
BOOTSTRAP_LOCK="/tmp/turboflow-bootstrap.lock"
BOOTSTRAP_DONE="$HOME/.turboflow-bootstrap-done"

cat > "$BOOTSTRAP_SCRIPT" << BOOTSTRAPEOF
#!/bin/bash
# TurboFlow 4.0 — Post-Setup Bootstrap (auto-runs once, then self-removes)
# This script completes deferred work that was too memory-heavy for setup.

set -uo pipefail

BSLOG="$BOOTSTRAP_LOG"
LOCK="$BOOTSTRAP_LOCK"
DONE_FLAG="$BOOTSTRAP_DONE"
WORKSPACE="$WORKSPACE"

# Already completed
[ -f "\$DONE_FLAG" ] && exit 0

# Prevent concurrent runs
if [ -f "\$LOCK" ]; then
    LOCK_PID=\$(cat "\$LOCK" 2>/dev/null)
    if [ -n "\$LOCK_PID" ] && kill -0 "\$LOCK_PID" 2>/dev/null; then
        exit 0  # Another instance is running
    fi
fi
echo \$\$ > "\$LOCK"
trap 'rm -f "\$LOCK"' EXIT

echo "[\$(date)] Bootstrap starting" >> "\$BSLOG"

# Cap all Node operations to 512MB
export NODE_OPTIONS="--max-old-space-size=512"

# --- 1. Retry GitNexus install if missing ---
if ! command -v gitnexus &>/dev/null; then
    echo "[\$(date)] Installing GitNexus..." >> "\$BSLOG"
    npm install -g gitnexus >> "\$BSLOG" 2>&1 || true
fi

# --- 2. Install Dolt if missing (Beads database backend) ---
if ! command -v dolt &>/dev/null; then
    echo "[\$(date)] Installing Dolt (Beads database backend)..." >> "\$BSLOG"
    (
        DOLT_ARCH=\$(uname -m)
        case "\$DOLT_ARCH" in
            x86_64|amd64) DOLT_ARCH="amd64" ;;
            aarch64|arm64) DOLT_ARCH="arm64" ;;
            *) DOLT_ARCH="amd64" ;;
        esac
        curl -L "https://github.com/dolthub/dolt/releases/latest/download/dolt-linux-\${DOLT_ARCH}.tar.gz" \
            -o /tmp/dolt.tar.gz 2>/dev/null
        sudo tar -xzf /tmp/dolt.tar.gz -C /usr/local/bin/ 2>/dev/null
        if [ -d "/usr/local/bin/dolt/bin" ]; then
            sudo cp /usr/local/bin/dolt/bin/dolt /usr/local/bin/dolt-bin 2>/dev/null
            sudo rm -rf /usr/local/bin/dolt 2>/dev/null
            sudo mv /usr/local/bin/dolt-bin /usr/local/bin/dolt 2>/dev/null
        fi
        sudo chmod +x /usr/local/bin/dolt 2>/dev/null
        rm -f /tmp/dolt.tar.gz
    ) >> "\$BSLOG" 2>&1
fi

# --- 3. Retry Beads install if missing ---
if ! command -v bd &>/dev/null; then
    echo "[\$(date)] Installing Beads..." >> "\$BSLOG"
    npm install -g beads-cli >> "\$BSLOG" 2>&1 || true
fi
if ! command -v bd &>/dev/null; then
    pip install --user beads >> "\$BSLOG" 2>&1 || true
fi

# --- 4. Initialize Beads in workspace ---
if command -v bd &>/dev/null && [ -d "\$WORKSPACE/.git" ]; then
    if [ ! -d "\$WORKSPACE/.beads" ]; then
        echo "[\$(date)] Initializing Beads in workspace..." >> "\$BSLOG"
        (cd "\$WORKSPACE" && bd init >> "\$BSLOG" 2>&1) || true
    fi
fi

# --- 5. Index workspace with GitNexus ---
if [ -d "\$WORKSPACE/.git" ]; then
    if command -v gitnexus &>/dev/null; then
        echo "[\$(date)] Indexing workspace with GitNexus..." >> "\$BSLOG"
        (cd "\$WORKSPACE" && gitnexus analyze >> "\$BSLOG" 2>&1) || true
    else
        # Fallback to npx with tight memory
        echo "[\$(date)] Indexing workspace with GitNexus (npx)..." >> "\$BSLOG"
        (cd "\$WORKSPACE" && npx -y gitnexus analyze >> "\$BSLOG" 2>&1) || true
    fi
fi

# --- 6. Register GitNexus MCP if not already done ---
if command -v gitnexus &>/dev/null || npx gitnexus --version >> "\$BSLOG" 2>&1; then
    npx gitnexus setup >> "\$BSLOG" 2>&1 \
        || claude mcp add gitnexus -- npx -y gitnexus mcp >> "\$BSLOG" 2>&1 \
        || true
fi

# --- Done — mark complete and remove shell hooks ---
touch "\$DONE_FLAG"
echo "[\$(date)] Bootstrap complete" >> "\$BSLOG"

# Remove the one-shot hook from shell rc files
for rc in "\$HOME/.bashrc" "\$HOME/.zshrc"; do
    [ -f "\$rc" ] && sed -i '/turboflow-bootstrap/d' "\$rc" 2>/dev/null || true
done

rm -f "\$LOCK"
BOOTSTRAPEOF

chmod +x "$BOOTSTRAP_SCRIPT"

# --- Trigger A: Launch immediately in background ---
# The nohup + disown ensures it survives after setup.sh exits.
# Sleep 5s to let setup finish and free all memory first.
(sleep 5 && nohup "$BOOTSTRAP_SCRIPT" >> "$BOOTSTRAP_LOG" 2>&1 &) &
disown 2>/dev/null || true
ok "Post-setup bootstrap launched (background, 5s delay)"

# --- Trigger B: One-shot shell hook (fallback if background process is killed) ---
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
echo -e "    Memory:  Beads + Native Tasks + AgentDB (3-tier)"
echo -e "    Graph:   GitNexus codebase knowledge graph"
echo -e "    Time:    ${TOTAL_TIME}s"
if [ "$NEEDS_BOOTSTRAP" -eq 1 ]; then
echo -e "    ${YELLOW}Bootstrap:${NC} finishing deferred installs in background (~30-60s)"
fi
echo ""
echo -e "  ${BOLD}Next:${NC} ${CYAN}claude${NC}  (everything else is automatic)"
echo ""
echo -e "  ${BOLD}Changed from v3.4.1:${NC}"
echo -e "    • claude-flow@alpha → ${GREEN}ruflo@latest${NC} (rf-* aliases)"
echo -e "    • 15 plugins → ${GREEN}6 plugins${NC} (9 redundant/domain-specific removed)"
echo -e "    • Slash commands → ${GREEN}skills${NC} (auto-activated)"
echo -e "    • No cross-session memory → ${GREEN}Beads${NC} (bd-* aliases)"
echo -e "    • No codebase awareness → ${GREEN}GitNexus${NC} (gnx-* aliases)"
echo -e "    • Manual worktree skill → ${GREEN}native wt-* helpers${NC}"
echo -e "    • 4 separate core installs → ${GREEN}1 ruflo init${NC}"
echo ""
echo -e "  ${BOLD}Logs:${NC} setup=$LOG  bootstrap=$BOOTSTRAP_LOG"
echo ""
exit 0
