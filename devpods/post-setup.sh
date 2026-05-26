#!/bin/bash
# =============================================================================
# TurboFlow 4.0 Post-Setup Verification Script
# Replaces: post-setup.sh from v3.4.1
#
# Verifies and configures all components installed by devpods/setup.sh:
#   - Claude Code + Ruflo v3.5
#   - 6 Ruflo plugins + OpenSpec
#   - GitNexus codebase knowledge graph
#   - Beads cross-session memory
#   - Native Agent Teams
#   - Statusline Pro
#   - CLAUDE.md + workspace + aliases
#
# FIX: PATH setup now checks NPM_CONFIG_PREFIX (uppercase, set by containerEnv)
#      in addition to npm_config_prefix (lowercase, set by npm).
# FIX: Plugin check searches multiple possible install locations.
# FIX: MCP config check includes ~/.claude/settings.local.json and project .mcp.json.
# FIX: Beads/GitNexus detection checks ~/.npm-global/bin explicitly.
# FIX 12: MCP autoStart check added to Ruflo MCP verification.
# FIX 13: Daemon auto-start verification added.
# FIX 14: Security scan verification added.
# FIX 15: GitNexus --force flag check added.
# =============================================================================

# Get the directory where this script is located
readonly DEVPOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PATH setup — check both uppercase (containerEnv) and lowercase (npm native) prefix
if [ -n "$NPM_CONFIG_PREFIX" ]; then
    export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
elif [ -n "$npm_config_prefix" ]; then
    export PATH="$npm_config_prefix/bin:$PATH"
elif [ -f "$HOME/.npmrc" ]; then
    _NPM_PREFIX=$(grep '^prefix=' "$HOME/.npmrc" 2>/dev/null | cut -d= -f2)
    [ -n "$_NPM_PREFIX" ] && export PATH="$_NPM_PREFIX/bin:$PATH"
fi
# Always include these
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.claude/bin:$PATH"

# Source aliases so Agent Teams env var and other exports are available
[ -f "$HOME/.turboflow_aliases" ] && source "$HOME/.turboflow_aliases"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

success() { echo -e "  ${GREEN}✓${NC} $*"; }
warning() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail()    { echo -e "  ${RED}✗${NC} $*"; }
info()    { echo -e "  ${BLUE}ℹ${NC} $*"; }
section() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

WORKSPACE="${WORKSPACE_FOLDER:=$(pwd)}"
ISSUES=0
PASS=0

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      🔍 TurboFlow 4.0 Post-Setup Verify         ║"
echo "║   Ruflo v3.5 + Beads + Worktrees + Agent Teams  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Workspace: $WORKSPACE"
echo ""

# =============================================================================
# STEP 1: Core Installations
# =============================================================================
section "Step 1: Core Installations"

# Build tools
if command -v g++ >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    success "Build tools (g++, make)"
    ((PASS++))
else
    warning "Build tools not found"
    ((ISSUES++))
fi

# jq
if command -v jq >/dev/null 2>&1; then
    success "jq $(jq --version 2>/dev/null)"
    ((PASS++))
else
    warning "jq not found (needed for statusline)"
    ((ISSUES++))
fi

# Node.js
if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node -v)
    NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 20 ]; then
        success "Node.js $NODE_VER"
        ((PASS++))
    else
        warning "Node.js $NODE_VER (v20+ required for Ruflo v3.5)"
        ((ISSUES++))
    fi
else
    fail "Node.js not found"
    ((ISSUES++))
fi

# Claude Code
if command -v claude >/dev/null 2>&1; then
    success "Claude Code $(claude --version 2>/dev/null | head -1)"
    ((PASS++))
else
    fail "Claude Code not found — run: curl -fsSL https://claude.ai/install.sh | bash"
    ((ISSUES++))
fi

# Ruflo
RF_VERSION=$(npx ruflo@latest --version 2>/dev/null | head -1 || echo "")
if [ -n "$RF_VERSION" ]; then
    success "Ruflo $RF_VERSION"
    ((PASS++))
else
    fail "Ruflo not responding — run: npx ruflo@latest init"
    ((ISSUES++))
fi

# =============================================================================
# STEP 2: Ruflo MCP + Doctor
# =============================================================================
section "Step 2: Ruflo MCP + Health Check"

# MCP registration — check all known config locations
MCP_OK=false
for cfg in "$HOME/.config/claude/mcp.json" \
           "$HOME/.claude/claude_desktop_config.json" \
           "$HOME/.claude/settings.local.json" \
           "$WORKSPACE/.mcp.json" \
           "$WORKSPACE/.claude/mcp.json"; do
    if [ -f "$cfg" ] && grep -q "ruflo" "$cfg" 2>/dev/null; then
        MCP_OK=true
        break
    fi
done

# Also check via claude mcp list if available
if ! $MCP_OK && command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -q "ruflo" 2>/dev/null; then
        MCP_OK=true
    fi
fi

if $MCP_OK; then
    success "Ruflo MCP server registered"
    ((PASS++))

    # FIX 12: Check for autoStart enabled
    AUTOSTART_OK=false
    for cfg in "$WORKSPACE/.mcp.json" "$HOME/.config/claude/mcp.json" "$HOME/.claude/settings.local.json"; do
        if [ -f "$cfg" ] && grep -q '"autoStart"\s*:\s*true' "$cfg" 2>/dev/null; then
            AUTOSTART_OK=true
            break
        fi
    done

    if $AUTOSTART_OK; then
        success "Ruflo MCP autoStart enabled"
        ((PASS++))
    else
        warning "Ruflo MCP autoStart not configured — enables on next setup run"
        ((ISSUES++))
    fi
else
    warning "Ruflo MCP not found in config — resolves automatically on first 'claude' launch"
    ((ISSUES++))
fi

# Check for stale claude-flow registration
for cfg in "$HOME/.config/claude/mcp.json" "$HOME/.claude/claude_desktop_config.json"; do
    if [ -f "$cfg" ] && grep -q "claude-flow" "$cfg" 2>/dev/null; then
        warning "Stale claude-flow MCP registration found in $cfg — run: claude mcp remove claude-flow"
        ((ISSUES++))
    fi
done

# Doctor
DOCTOR_OUTPUT=$(npx ruflo@latest doctor 2>&1 || true)
if echo "$DOCTOR_OUTPUT" | grep -qi "error\|failed\|critical"; then
    warning "Ruflo doctor found issues:"
    echo "$DOCTOR_OUTPUT" | head -10 | sed 's/^/    /'
    ((ISSUES++))
else
    success "Ruflo doctor passed"
    ((PASS++))
fi

# =============================================================================
# STEP 3: Ruflo Plugins
# =============================================================================
section "Step 3: Ruflo Plugins (6)"

# Plugins can be installed in multiple locations depending on ruflo version
PLUGIN_DIRS=(
    "$WORKSPACE/.claude-flow/plugins"
    "$WORKSPACE/.ruflo/plugins"
    "$WORKSPACE/node_modules/@claude-flow"
    "$HOME/.claude-flow/plugins"
    "$HOME/.ruflo/plugins"
)

check_plugin() {
    local name="$1"
    local display="$2"
    local found=false

    for pdir in "${PLUGIN_DIRS[@]}"; do
        if [ -d "$pdir/$name" ] && [ -f "$pdir/$name/package.json" ]; then
            found=true
            break
        fi
    done

    # Also check via ruflo plugins list
    if ! $found; then
        if npx ruflo@latest plugins list 2>/dev/null | grep -qi "$(echo "$name" | sed 's/@claude-flow\///')" 2>/dev/null; then
            found=true
        fi
    fi

    # Also check npm node_modules (fallback for direct npm installs)
    if ! $found && [ -f "$WORKSPACE/node_modules/$name/package.json" ]; then
        found=true
    fi

    if $found; then
        success "$display"
        ((PASS++))
    else
        warning "$display — not found (run: npx ruflo@latest plugins install -n $name)"
        ((ISSUES++))
    fi
}

check_plugin "@claude-flow/plugin-agentic-qe" "Agentic QE (58 QE agents, TDD, coverage)"
check_plugin "@claude-flow/plugin-code-intelligence" "Code Intelligence (analysis, patterns)"
check_plugin "@claude-flow/plugin-test-intelligence" "Test Intelligence (generation, gap analysis)"
check_plugin "@claude-flow/plugin-perf-optimizer" "Perf Optimizer (profiling, bottlenecks)"
check_plugin "@claude-flow/teammate-plugin" "Teammate Plugin (Agent Teams bridge, 21 MCP tools)"
check_plugin "@claude-flow/plugin-gastown-bridge" "Gastown Bridge (WASM orchestration, 20 MCP tools)"

# =============================================================================
# STEP 4: OpenSpec
# =============================================================================
section "Step 4: OpenSpec"

if npm list -g @fission-ai/openspec --depth=0 >/dev/null 2>&1; then
    success "OpenSpec installed globally"
    ((PASS++))
elif npx @fission-ai/openspec --version >/dev/null 2>&1; then
    success "OpenSpec available via npx"
    ((PASS++))
else
    warning "OpenSpec not installed — run: npm i -g @fission-ai/openspec"
    ((ISSUES++))
fi

# =============================================================================
# STEP 5: UI UX Pro Max Skill
# =============================================================================
section "Step 5: UI UX Pro Max Skill"

UIPRO_SKILL_DIR="$HOME/.claude/skills/ui-ux-pro-max"
UIPRO_SKILL_DIR_LOCAL="$WORKSPACE/.claude/skills/ui-ux-pro-max"

if [ -d "$UIPRO_SKILL_DIR" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR" 2>/dev/null)" ]; then
    success "UI UX Pro Max skill installed (global)"
    ((PASS++))
elif [ -d "$UIPRO_SKILL_DIR_LOCAL" ] && [ -n "$(ls -A "$UIPRO_SKILL_DIR_LOCAL" 2>/dev/null)" ]; then
    success "UI UX Pro Max skill installed (local)"
    ((PASS++))
else
    warning "UI UX Pro Max skill missing — run: npx uipro-cli init --ai claude"
    ((ISSUES++))
fi

# =============================================================================
# STEP 6: GitNexus
# =============================================================================
section "Step 6: GitNexus (Codebase Knowledge Graph)"

if command -v gitnexus >/dev/null 2>&1; then
    success "GitNexus installed globally"
    ((PASS++))
elif npx gitnexus --version >/dev/null 2>&1; then
    success "GitNexus available via npx"
    ((PASS++))
else
    warning "GitNexus not installed — run: npm i -g gitnexus"
    ((ISSUES++))
fi

# GitNexus MCP — check all known config locations
GNX_MCP=false
for cfg in "$HOME/.config/claude/mcp.json" \
           "$HOME/.claude/claude_desktop_config.json" \
           "$HOME/.claude/settings.local.json" \
           "$WORKSPACE/.mcp.json" \
           "$WORKSPACE/.claude/mcp.json"; do
    if [ -f "$cfg" ] && grep -q "gitnexus" "$cfg" 2>/dev/null; then
        GNX_MCP=true
        break
    fi
done

if ! $GNX_MCP && command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -q "gitnexus" 2>/dev/null; then
        GNX_MCP=true
    fi
fi

if $GNX_MCP; then
    success "GitNexus MCP server registered"
    ((PASS++))

    # Verify GitNexus MCP actually responds.
    # NOTE: `claude mcp call` / `claude mcp restart` are NOT real Claude CLI
    # subcommands. Use `claude mcp list` (reports per-server health) and a direct
    # CLI probe instead. MCP servers (re)connect when Claude Code launches.
    GNX_RESPONDS=false
    if command -v claude >/dev/null 2>&1 && \
       claude mcp list 2>/dev/null | grep -i "gitnexus" | grep -qi "connected"; then
        success "GitNexus MCP server connected"
        ((PASS++))
        GNX_RESPONDS=true
    fi

    if ! $GNX_RESPONDS; then
        # Fall back to a direct CLI probe (server connects on next 'claude' launch)
        if (command -v gitnexus >/dev/null 2>&1 && timeout 8 gitnexus list >/dev/null 2>&1) || \
           timeout 15 npx -y gitnexus list >/dev/null 2>&1; then
            success "GitNexus engine responding (MCP connects on next 'claude' launch)"
            ((PASS++))
        else
            warning "GitNexus MCP not responding yet — connects on next 'claude' launch"
            ((ISSUES++))
        fi
    fi
else
    warning "GitNexus MCP not registered — resolves automatically on first 'claude' launch"
    ((ISSUES++))
fi

# Workspace indexed?
if [ -d "$WORKSPACE/.git" ]; then
    if [ -d "$WORKSPACE/.gitnexus" ] || [ -f "$WORKSPACE/.gitnexus.json" ] || [ -f "$WORKSPACE/.gitnexus.db" ]; then
        success "Workspace indexed by GitNexus"
        ((PASS++))

        # FIX 15: Check if indexed with --force flag (for proper execution flow detection)
        if [ -f "$WORKSPACE/.gitnexus/meta.json" ]; then
            # Check if processes/execution flows exist (indicates --force was used)
            PROCESS_COUNT=$(jq -r '.stats.processes // 0' "$WORKSPACE/.gitnexus/meta.json" 2>/dev/null || echo "0")
            if [ "$PROCESS_COUNT" -gt 0 ]; then
                success "GitNexus indexed with --force (execution flows detected: $PROCESS_COUNT)"
                ((PASS++))
            else
                info "GitNexus indexed but may need --force for execution flows — run: gnx-analyze-force"
            fi
        fi
    else
        info "Workspace not indexed — run: gnx-analyze-force"
    fi
fi

# Fix GitNexus database permissions (causes "read-only database" FTS write errors).
# Ensure the current user owns the dir and has read/write on the DB files.
if [ -d "$WORKSPACE/.gitnexus" ]; then
    chown -R "$(whoami)":"$(whoami)" "$WORKSPACE/.gitnexus" 2>/dev/null || true
    chmod -R u+rw "$WORKSPACE/.gitnexus" 2>/dev/null || true
    if [ -f "$WORKSPACE/.gitnexus/meta.json" ]; then
        success "GitNexus database permissions fixed (owner read/write)"
    fi
fi

# Check if any repos are actually indexed (GitNexus may be installed but empty).
# Correct subcommand is `gitnexus list` (human-readable, not `list-repos`/JSON).
if command -v gitnexus >/dev/null 2>&1 || npx gitnexus --version >/dev/null 2>&1; then
    GNX_LIST=$( (command -v gitnexus >/dev/null 2>&1 && gitnexus list 2>/dev/null) || npx -y gitnexus list 2>/dev/null || echo "")
    REPO_COUNT=$(echo "$GNX_LIST" | grep -ciE "Path:|Indexed:" 2>/dev/null || echo "0")
    if [ "${REPO_COUNT:-0}" -gt 0 ]; then
        success "GitNexus has $REPO_COUNT repo(s) indexed"
        ((PASS++))
    else
        info "GitNexus installed but no repos indexed — run: gnx-analyze-force"
    fi
fi

# =============================================================================
# STEP 7: Beads (Cross-Session Memory)
# =============================================================================
section "Step 7: Beads (Cross-Session Memory)"

if command -v bd >/dev/null 2>&1; then
    success "Beads CLI installed"
    ((PASS++))
else
    # Check if it's in npm-global but not on PATH yet
    if [ -x "$HOME/.npm-global/bin/bd" ]; then
        success "Beads CLI installed (in ~/.npm-global/bin)"
        ((PASS++))
    else
        warning "Beads not installed — run: npm i -g @beads/bd"
        ((ISSUES++))
    fi
fi

# Ensure Beads is not just present but actually usable (DB reachable).
if command -v bd >/dev/null 2>&1 && [ -d "$WORKSPACE/.git" ]; then
    # Role is required for Beads routing.
    git config beads.role maintainer 2>/dev/null || true

    # First init if never initialized.
    if [ ! -d "$WORKSPACE/.beads" ] && [ ! -f "$WORKSPACE/.beads.json" ]; then
        info "Beads not initialized — running bd init..."
        (cd "$WORKSPACE" && bd init >/dev/null 2>&1) || true
    fi

    # Self-heal: if the directory exists but the Dolt-backed DB is unreachable
    # (e.g. server restarted, fresh clone), bootstrap recreates the database.
    if [ -d "$WORKSPACE/.beads" ] && ! (cd "$WORKSPACE" && bd status >/dev/null 2>&1); then
        info "Beads database unreachable — running bd bootstrap..."
        (cd "$WORKSPACE" && bd bootstrap >/dev/null 2>&1) || true
    fi
fi

if [ -d "$WORKSPACE/.beads" ] || [ -f "$WORKSPACE/.beads.json" ]; then
    if command -v bd >/dev/null 2>&1 && (cd "$WORKSPACE" && bd status >/dev/null 2>&1); then
        success "Beads initialized and database reachable"
        ((PASS++))

        # FIX 17: Check if there are any Beads entries (project memory)
        BEADS_COUNT=$( (cd "$WORKSPACE" && bd list 2>/dev/null | wc -l) || echo "0")
        if [ "${BEADS_COUNT:-0}" -gt 0 ]; then
            success "Project memory has $BEADS_COUNT Beads entries"
            ((PASS++))
        else
            info "No Beads entries yet — run: bd create 'Title' -t decision -p 0 --description 'Context'"
        fi
    else
        warning "Beads directory present but database not reachable — run: bd bootstrap"
        ((ISSUES++))
    fi
else
    if [ -d "$WORKSPACE/.git" ]; then
        info "Beads not initialized — run: bd init"
    else
        info "Not a git repo — Beads requires git"
    fi
fi

# =============================================================================
# STEP 8: Agent Teams + Environment
# FIX 17: Added checks for .worktrees and .claude/teams directories
# =============================================================================
section "Step 8: Agent Teams + Environment"

if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" = "1" ]; then
    success "Agent Teams enabled (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)"
    ((PASS++))
else
    # Check if it's in the alias file even if not exported in this shell
    if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' "$HOME/.turboflow_aliases" 2>/dev/null; then
        success "Agent Teams configured in aliases (active after: source ~/.bashrc)"
        ((PASS++))
    else
        warning "Agent Teams not enabled — add to shell: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
        ((ISSUES++))
    fi
fi

# FIX 17: Check for .worktrees directory (agent isolation)
if [ -d "$WORKSPACE/.worktrees" ]; then
    success "Worktrees directory exists (.worktrees/)"
    ((PASS++))
else
    warning "Worktrees directory missing — parallel agents will share main working tree"
    ((ISSUES++))
fi

# FIX 17: Check for .claude/teams directory (persistent agent teams)
if [ -d "$WORKSPACE/.claude/teams" ]; then
    success "Agent Teams directory exists (.claude/teams/)"
    ((PASS++))
else
    warning "Agent Teams directory missing — run: mkdir -p \$WORKSPACE/.claude/teams"
    ((ISSUES++))
fi

# Check alias file
ALIAS_FILE="$HOME/.turboflow_aliases"
if [ -f "$ALIAS_FILE" ]; then
    success "Alias file exists: $ALIAS_FILE"
    ((PASS++))

    # Check it's sourced
    SOURCED=false
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ] && grep -q 'turboflow_aliases' "$rc" 2>/dev/null; then
            SOURCED=true
            break
        fi
    done
    if $SOURCED; then
        success "Aliases sourced in shell rc"
        ((PASS++))
    else
        warning "Aliases not sourced — add to .bashrc: [ -f \"$ALIAS_FILE\" ] && source \"$ALIAS_FILE\""
        ((ISSUES++))
    fi

    # Check for stale v3.x aliases
    if grep -q '# === TURBO FLOW' "$HOME/.bashrc" 2>/dev/null; then
        warning "Stale v3.x alias block found in .bashrc — should have been cleaned by setup"
        ((ISSUES++))
    fi
else
    fail "Alias file missing — run devpods/setup.sh"
    ((ISSUES++))
fi

# Key aliases spot check
section "Alias Spot Check"
for alias_name in rf rf-swarm rf-daemon bd-ready wt-list gnx-analyze gnx-analyze-force aqe-generate os; do
    if grep -q "$alias_name" "$ALIAS_FILE" 2>/dev/null; then
        success "Alias: $alias_name"
    else
        warning "Alias missing: $alias_name"
        ((ISSUES++))
    fi
done

# Key functions
for func in turbo-status turbo-help wt-add rf-spawn; do
    if grep -q "${func}" "$ALIAS_FILE" 2>/dev/null; then
        success "Function: $func"
    else
        warning "Function missing: $func"
        ((ISSUES++))
    fi
done

# =============================================================================
# STEP 9: Statusline Pro
# =============================================================================
section "Step 9: Statusline Pro"

STATUSLINE_SCRIPT="$HOME/.claude/turbo-flow-statusline.sh"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

if [ -f "$STATUSLINE_SCRIPT" ]; then
    success "Statusline script exists"
    ((PASS++))
    if [ -x "$STATUSLINE_SCRIPT" ]; then
        success "Statusline script is executable"
        ((PASS++))
    else
        warning "Statusline not executable — fixing..."
        chmod +x "$STATUSLINE_SCRIPT"
        ((ISSUES++))
    fi
else
    fail "Statusline script missing — run devpods/setup.sh"
    ((ISSUES++))
fi

if [ -f "$CLAUDE_SETTINGS" ] && grep -q "turbo-flow-statusline" "$CLAUDE_SETTINGS" 2>/dev/null; then
    success "Statusline configured in settings.json"
    ((PASS++))
else
    warning "Statusline not configured in settings.json"
    ((ISSUES++))
fi

# =============================================================================
# STEP 10: CLAUDE.md + Workspace
# =============================================================================
section "Step 10: CLAUDE.md + Workspace"

if [ -f "$WORKSPACE/CLAUDE.md" ]; then
    success "CLAUDE.md exists"
    ((PASS++))

    # Check it's the v4.0 version
    if grep -q "TurboFlow 4.0" "$WORKSPACE/CLAUDE.md" 2>/dev/null; then
        success "CLAUDE.md is v4.0"
        ((PASS++))
    else
        warning "CLAUDE.md exists but may be outdated — check for 'TurboFlow 4.0' header"
        ((ISSUES++))
    fi
else
    fail "CLAUDE.md missing — run devpods/setup.sh"
    ((ISSUES++))
fi

# FIX 17: Check AGENTS_DIR environment variable
if [ -n "${AGENTS_DIR:-}" ]; then
    success "AGENTS_DIR set: $AGENTS_DIR"
    ((PASS++))
    if [ -d "$AGENTS_DIR" ]; then
        success "Agents directory exists"
        ((PASS++))
    else
        warning "Agents directory does not exist — run: mkdir -p \$AGENTS_DIR"
        ((ISSUES++))
    fi
else
    info "AGENTS_DIR not set — add to shell: export AGENTS_DIR=\"\$WORKSPACE/agents\""
fi

# Workspace directories
for dir in src tests docs scripts config plans; do
    if [ -d "$WORKSPACE/$dir" ]; then
        success "Directory: $dir/"
    else
        warning "Missing directory: $dir/"
        ((ISSUES++))
    fi
done

# =============================================================================
# STEP 11: Security Scan
# FIX 14: Security scan verification
# =============================================================================
section "Step 11: Security Scan"

# Security is handled by Ruflo's built-in AIDefence (claude-flow@alpha is the dead
# package this migration removed — do NOT reintroduce @claude-flow/cli here).
if npx ruflo@latest aidefence stats >/dev/null 2>&1; then
    success "Security scanning available (Ruflo AIDefence)"
    ((PASS++))
    info "Run security scan: npx ruflo@latest aidefence scan"
else
    warning "Ruflo AIDefence not responding — run: npx ruflo@latest aidefence stats"
    ((ISSUES++))
fi

# =============================================================================
# STEP 12: Ruflo Daemon
# FIX 13: Daemon auto-start verification + retry startup
# =============================================================================
section "Step 12: Ruflo Daemon"

DAEMON_RUNNING=false
if npx ruflo@latest daemon status 2>/dev/null | grep -qi "running"; then
    success "Ruflo daemon already running"
    ((PASS++))
    DAEMON_RUNNING=true
else
    info "Ruflo daemon not running — attempting to start..."
    # Try starting with retry (up to 3 attempts)
    for attempt in 1 2 3; do
        if npx ruflo@latest daemon start --timeout 30 >/dev/null 2>&1; then
            sleep 5  # Give daemon time to initialize
            if npx ruflo@latest daemon status 2>/dev/null | grep -qi "running"; then
                success "Ruflo daemon started (attempt $attempt)"
                ((PASS++))
                DAEMON_RUNNING=true
                break
            fi
        fi
        [ $attempt -lt 3 ] && sleep 2
    done
fi

if ! $DAEMON_RUNNING; then
    warning "Ruflo daemon failed to start — try manually: rf-daemon"
    ((ISSUES++))
fi

# =============================================================================
# STEP 13: API Keys + PATH
# =============================================================================
section "Step 13: Environment"

[ -n "${ANTHROPIC_API_KEY:-}" ] && { success "ANTHROPIC_API_KEY is set"; ((PASS++)); } || { info "ANTHROPIC_API_KEY not set — set via: export ANTHROPIC_API_KEY=\"sk-ant-...\" (or authenticate via 'claude' on first launch)"; }
echo "$PATH" | grep -q ".local/bin" && { success "PATH includes ~/.local/bin"; ((PASS++)); } || { warning "PATH missing ~/.local/bin"; ((ISSUES++)); }
echo "$PATH" | grep -q ".claude/bin" && { success "PATH includes ~/.claude/bin"; ((PASS++)); } || { warning "PATH missing ~/.claude/bin"; ((ISSUES++)); }
echo "$PATH" | grep -q ".npm-global/bin" && { success "PATH includes ~/.npm-global/bin"; ((PASS++)); } || { warning "PATH missing ~/.npm-global/bin"; ((ISSUES++)); }

# =============================================================================
# STEP 14: Fix Permissions
# =============================================================================
section "Step 14: Permissions"

CURRENT_USER=$(whoami)
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.claude" 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.local" 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.npm-global" 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$HOME/.config/claude" 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" /home/"$CURRENT_USER"/.vscode-server 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" /workspaces/.cache/vscode-server 2>/dev/null || true
sudo chown -R "$CURRENT_USER:$CURRENT_USER" /workspaces/.cache/npm-global 2>/dev/null || true
success "Permissions fixed"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      Post-Setup Verification Complete            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo -e "  Results: ${GREEN}$PASS passed${NC}  /  ${YELLOW}$ISSUES issues${NC}"
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed!${NC}"
else
    echo -e "  ${YELLOW}$ISSUES issue(s) found — review warnings above.${NC}"
fi

echo ""
echo "  Next Steps:"
echo "    1. RESTART CLAUDE CODE  →  Required for MCP & plugins"
echo "    2. RELOAD SHELL         →  source ~/.bashrc"
echo "    3. SET API KEY          →  export ANTHROPIC_API_KEY=\"sk-ant-...\""
echo "    4. VERIFY               →  turbo-status"
echo "    5. SECURITY SCAN        →  npx ruflo@latest aidefence scan"
echo ""
echo "  Quick Reference:"
echo "    ORCHESTRATION   rf-swarm, rf-spawn, rf-doctor, rf-daemon"
echo "    MEMORY          bd-ready, bd-add, ruv-remember, mem-search"
echo "    ISOLATION       wt-add, wt-remove, wt-list"
echo "    QUALITY         aqe-generate, aqe-gate, os-init"
echo "    INTELLIGENCE    hooks-train, hooks-route, neural-train"
echo "    CODEBASE        gnx-analyze-force, gnx-serve, gnx-wiki"
echo "    SECURITY        npx ruflo@latest aidefence scan"
echo "    STATUS          turbo-status, turbo-help"
echo ""
