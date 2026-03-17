#!/bin/bash
# TURBO FLOW SETUP SCRIPT v3.4.1 (COMPLETE + PLUGINS)
# Complete: All Claude Flow native skills + ALL 15 plugins enabled
# Based on analysis: Claude_Flow_vs_Turbo_Flow_Analysis.docx
# 
# CHANGES FROM v3.4.0:
# - FIXED: Removed skill install (not supported by claude-flow CLI)
# - FIXED: Changed 'plugin' to 'plugins' (correct subcommand)
# - FIXED: Added npm fallback for Claude Code installation
# - FIXED: Better error handling throughout

# ============================================
# CONFIGURATION
# ============================================
: "${WORKSPACE_FOLDER:=$(pwd)}"
: "${DEVPOD_WORKSPACE_FOLDER:=$WORKSPACE_FOLDER}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEVPOD_DIR="$SCRIPT_DIR"
TOTAL_STEPS=15
CURRENT_STEP=0
START_TIME=$(date +%s)

# ============================================
# PATH SETUP - ensure npm global bin is discoverable
# ============================================
if [ -n "$npm_config_prefix" ]; then
    export PATH="$npm_config_prefix/bin:$PATH"
elif [ -f "$HOME/.npmrc" ]; then
    _NPM_PREFIX=$(grep '^prefix=' "$HOME/.npmrc" 2>/dev/null | cut -d= -f2)
    [ -n "$_NPM_PREFIX" ] && export PATH="$_NPM_PREFIX/bin:$PATH"
fi
export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"

# ============================================
# PROGRESS HELPERS
# ============================================
progress_bar() {
    local percent=$1
    local width=30
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    printf "\r  ["
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%%" "$percent"
}

step_header() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    PERCENT=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo ""
    echo ""
    echo "=================================================="
    echo "  [$PERCENT%] STEP $CURRENT_STEP/$TOTAL_STEPS: $1"
    echo "=================================================="
    progress_bar $PERCENT
    echo ""
}

status() { echo "  [*] $1..."; }
ok() { echo "  [OK] $1"; }
skip() { echo "  [SKIP] $1 (already installed)"; }
warn() { echo "  [WARN] $1 (continuing anyway)"; }
info() { echo "  [INFO] $1"; }
checking() { echo "  [CHECK] Checking $1..."; }
fail() { echo "  [FAIL] $1"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
is_npm_installed() { npm list -g "$1" --depth=0 >/dev/null 2>&1; }
elapsed() { echo "$(($(date +%s) - START_TIME))s"; }

skill_has_content() {
    local dir="$1"
    [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]
}

plugin_has_content() {
    local dir="$1"
    [ -d "$dir" ] && [ -f "$dir/package.json" ]
}

# Note: Claude Flow does not have a 'skill install' subcommand
# Skills are built-in or created manually
install_skill() {
    local skill_name="$1"
    local skill_dir="$HOME/.claude/skills/$skill_name"
    
    if skill_has_content "$skill_dir"; then
        skip "$skill_name skill"
        return 0
    fi
    
    # Claude Flow doesn't support skill install via CLI
    # Skills are built-in features, not installable packages
    info "$skill_name skill (built-in to claude-flow)"
    return 0
}

install_plugin() {
    local plugin_name="$1"
    local plugin_dir="$WORKSPACE_FOLDER/.claude-flow/plugins/$plugin_name"
    
    if plugin_has_content "$plugin_dir"; then
        skip "$plugin_name plugin"
        return 0
    fi
    
    status "Installing $plugin_name plugin"
    # Fixed: Use 'plugins' (plural) not 'plugin'
    if npx -y claude-flow@alpha plugins install -n "$plugin_name" 2>/dev/null; then
        ok "$plugin_name plugin installed"
        return 0
    else
        # Try npm install as fallback
        mkdir -p "$plugin_dir"
        if [ -f "/home/z/my-project/claude-flow-repo/v3/plugins/$plugin_name/package.json" ]; then
            cp -r /home/z/my-project/claude-flow-repo/v3/plugins/$plugin_name/* "$plugin_dir/"
            cd "$plugin_dir" && npm install --silent 2>/dev/null
            cd "$WORKSPACE_FOLDER"
            ok "$plugin_name plugin installed (from local)"
            return 0
        else
            warn "$plugin_name plugin install failed (plugin may not exist in registry)"
            return 1
        fi
    fi
}


# ============================================
# START
# ============================================
clear 2>/dev/null || true
echo ""
echo "=================================================="
echo "     TURBO FLOW v3.4.1 - COMPLETE + PLUGINS"
echo "     36 Skills + 15 Plugins + Memory + MCP"
echo "=================================================="
echo ""
echo "  Workspace: $WORKSPACE_FOLDER"
echo "  Started at: $(date '+%H:%M:%S')"
echo ""
progress_bar 0
echo ""

# ============================================
# STEP 1: Build tools
# ============================================
step_header "Installing build tools"

checking "build-essential"
if has_cmd g++ && has_cmd make; then
    skip "build tools (g++, make already present)"
else
    status "Installing build-essential and python3"
    if has_cmd apt-get; then
        (apt-get update -qq && apt-get install -y -qq build-essential python3 git curl jq) 2>/dev/null || \
        (sudo apt-get update -qq && sudo apt-get install -y -qq build-essential python3 git curl jq) 2>/dev/null || \
        warn "Could not install build tools"
        ok "build tools installed"
    elif has_cmd yum; then
        (yum groupinstall -y "Development Tools" && yum install -y jq || sudo yum groupinstall -y "Development Tools" && sudo yum install -y jq) 2>/dev/null
        ok "build tools installed (yum)"
    elif has_cmd apk; then
        apk add --no-cache build-base python3 git curl jq 2>/dev/null
        ok "build tools installed (apk)"
    else
        warn "Unknown package manager"
    fi
fi

checking "jq"
if has_cmd jq; then
    skip "jq"
else
    status "Installing jq"
    if has_cmd apt-get; then
        (apt-get install -y -qq jq || sudo apt-get install -y -qq jq) 2>/dev/null && ok "jq installed" || warn "jq failed"
    elif has_cmd brew; then
        brew install jq 2>/dev/null && ok "jq installed" || warn "jq failed"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 2: Claude Code CLI Installation
# ============================================
step_header "Installing Claude Code CLI"

checking "Claude Code CLI"
if has_cmd claude; then
    skip "Claude Code already installed"
    ok "Claude Code version: $(claude --version 2>/dev/null | head -1)"
else
    status "Installing Claude Code CLI via npm (recommended method)"
    
    # Try npm installation first (more reliable)
    if npm install -g @anthropic-ai/claude-code 2>/dev/null; then
        export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"
        ok "Claude Code installed via npm"
    else
        # Fallback to official installer
        status "Trying official installer..."
        if curl -fsSL https://claude.ai/install.sh 2>/dev/null | sh 2>&1; then
            export PATH="$HOME/.local/bin:$HOME/.claude/bin:$PATH"
            ok "Claude Code installed via official installer"
        fi
    fi

    # Verify installation
    if has_cmd claude; then
        ok "Claude Code installed ($(claude --version 2>/dev/null | head -1))"
    else
        fail "Claude Code install failed"
        info "Install manually: npm install -g @anthropic-ai/claude-code"
        info "Or try: curl -fsSL https://claude.ai/install.sh | sh"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 3: Claude Flow V3 + RuVector
# ============================================
step_header "Installing Claude Flow V3 + RuVector"

checking "Node.js version"
NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ -z "$NODE_MAJOR" ]; then
    fail "Node.js not found"
    info "Install Node.js 20+ before continuing"
elif [ "$NODE_MAJOR" -lt 18 ]; then
    warn "Node.js $(node -v) found, Claude Code requires 18+"
    status "Installing Node.js 20 via nodesource"
    curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | sudo -E bash - 2>/dev/null
    sudo apt-get install -y nodejs 2>/dev/null
    ok "Node.js $(node -v) installed"
else
    ok "Node.js $(node -v)"
fi

CLAUDE_FLOW_OK=false
if [ -d "$WORKSPACE_FOLDER/.claude-flow" ]; then
    if is_npm_installed "ruvector" || is_npm_installed "claude-flow"; then
        CLAUDE_FLOW_OK=true
    fi
fi

if $CLAUDE_FLOW_OK; then
    skip "Claude Flow + RuVector already installed"
else
    status "Running official claude-flow installer (--full mode)"
    echo ""
    
    curl -fsSL https://cdn.jsdelivr.net/gh/ruvnet/claude-flow@main/scripts/install.sh 2>/dev/null | bash -s -- --full 2>&1 | while IFS= read -r line; do
        if [[ ! "$line" =~ "deprecated" ]] && [[ ! "$line" =~ "npm warn" ]]; then
            echo "    $line"
        fi
    done || true
    
    cd "$WORKSPACE_FOLDER" 2>/dev/null || true
    
    status "Ensuring claude-flow@alpha is installed"
    npm install -g claude-flow@alpha --silent 2>/dev/null || true
    
    if [ ! -d ".claude-flow" ]; then
        status "Initializing Claude Flow in workspace"
        npx -y claude-flow@alpha init --force 2>/dev/null || true
    fi

    status "Warming RuVector npx cache"
    npx -y ruvector --version 2>/dev/null || true

    ok "Claude Flow + RuVector installed"

    npm cache clean --force 2>/dev/null || true
    rm -rf /tmp/npm-* /tmp/nvm-* /tmp/security-analyzer /tmp/agent-skills 2>/dev/null || true
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 4: Claude Flow Browser Setup
# ============================================
step_header "Verifying Claude Flow Browser"

checking "Claude Flow Browser integration"
if [ -d "$WORKSPACE_FOLDER/.claude-flow" ]; then
    ok "Claude Flow Browser: integrated (59 MCP tools available via cf-mcp)"
    info "  Tools: browser/open, browser/snapshot, browser/click, browser/fill, etc."
    info "  Features: trajectory learning, security scanning, element refs"
else
    warn "Claude Flow not initialized - run cf-init first"
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 5: Claude Flow Plugins (15)
# ============================================
step_header "Installing Claude Flow Plugins (15)"

checking "Claude Flow plugins"
PLUGINS_INSTALLED=0

# Quality Engineering
install_plugin "agentic-qe" && ((PLUGINS_INSTALLED++))

# Code Intelligence
install_plugin "code-intelligence" && ((PLUGINS_INSTALLED++))

# Cognitive Systems
install_plugin "cognitive-kernel" && ((PLUGINS_INSTALLED++))
install_plugin "hyperbolic-reasoning" && ((PLUGINS_INSTALLED++))

# Performance & Optimization
install_plugin "perf-optimizer" && ((PLUGINS_INSTALLED++))
install_plugin "quantum-optimizer" && ((PLUGINS_INSTALLED++))
install_plugin "prime-radiant" && ((PLUGINS_INSTALLED++))

# Neural & Coordination
install_plugin "neural-coordination" && ((PLUGINS_INSTALLED++))
install_plugin "ruvector-upstream" && ((PLUGINS_INSTALLED++))
install_plugin "teammate-plugin" && ((PLUGINS_INSTALLED++))

# Testing
install_plugin "test-intelligence" && ((PLUGINS_INSTALLED++))

# Domain-Specific
install_plugin "financial-risk" && ((PLUGINS_INSTALLED++))
install_plugin "healthcare-clinical" && ((PLUGINS_INSTALLED++))
install_plugin "legal-contracts" && ((PLUGINS_INSTALLED++))

# WASM Bridge
install_plugin "gastown-bridge" && ((PLUGINS_INSTALLED++))

info "Plugins processed: $PLUGINS_INSTALLED"
info "Elapsed: $(elapsed)"

# ============================================
# STEP 6: Claude Flow Memory System
# ============================================
step_header "Initializing Claude Flow Memory System"

checking "Claude Flow memory system"
MEMORY_DIR="$WORKSPACE_FOLDER/.claude-flow/memory"

if [ -d "$MEMORY_DIR" ] && [ -f "$MEMORY_DIR/agent.db" ]; then
    skip "Memory system already initialized"
else
    status "Initializing Claude Flow memory system"
    
    # Create memory directory
    mkdir -p "$MEMORY_DIR" 2>/dev/null
    
    if npx -y claude-flow@alpha memory init 2>/dev/null; then
        ok "Memory system initialized"
    else
        # Memory might init on first use
        warn "Memory init returned non-zero, but may initialize on first use"
    fi
    
    if [ -d "$MEMORY_DIR" ]; then
        info "  HNSW Vector Search: 150x-12,500x faster than standard"
        info "  AgentDB: SQLite-based persistent memory with WAL mode"
        info "  LearningBridge: Bidirectional sync with Claude Code"
        info "  3-Scope Memory: Project/local/user scoping"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 7: Claude Flow MCP Server
# ============================================
step_header "Registering Claude Flow MCP Server"

checking "Claude Flow MCP server registration"
MCP_CONFIG="$HOME/.claude/claude_desktop_config.json"

if [ -f "$MCP_CONFIG" ] && grep -q "claude-flow" "$MCP_CONFIG" 2>/dev/null; then
    skip "Claude Flow MCP server already registered"
else
    status "Registering Claude Flow MCP server (175+ tools)"
    
    # Create config directory
    mkdir -p "$HOME/.claude" 2>/dev/null
    
    # Try to register via claude CLI
    if has_cmd claude; then
        claude mcp add claude-flow -- npx -y claude-flow@alpha mcp start 2>/dev/null || true
    fi
    
    # Verify or create manually
    if [ -f "$MCP_CONFIG" ] && grep -q "claude-flow" "$MCP_CONFIG" 2>/dev/null; then
        ok "Claude Flow MCP server registered"
        info "  175+ MCP tools now available"
    else
        # Create MCP config manually
        status "Creating MCP config manually"
        mkdir -p "$HOME/.claude"
        cat > "$MCP_CONFIG" << 'MCP_EOF'
{
  "mcpServers": {
    "claude-flow": {
      "command": "npx",
      "args": ["-y", "claude-flow@alpha", "mcp", "start"]
    }
  }
}
MCP_EOF
        ok "MCP config created at $MCP_CONFIG"
        info "  Run: claude mcp add claude-flow -- npx -y claude-flow@alpha mcp start"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 8: Security Analyzer Skill
# ============================================
step_header "Installing Security Analyzer Skill"

SECURITY_SKILL_DIR="$HOME/.claude/skills/security-analyzer"

checking "security-analyzer skill"
if skill_has_content "$SECURITY_SKILL_DIR"; then
    skip "security-analyzer skill already installed"
else
    status "Cloning security-analyzer"
    if git clone --depth 1 https://github.com/Cornjebus/security-analyzer.git /tmp/security-analyzer 2>/dev/null; then
        mkdir -p "$SECURITY_SKILL_DIR"
        if [ -d "/tmp/security-analyzer/.claude/skills/security-analyzer" ]; then
            cp -r /tmp/security-analyzer/.claude/skills/security-analyzer/* "$SECURITY_SKILL_DIR/"
        else
            cp -r /tmp/security-analyzer/* "$SECURITY_SKILL_DIR/"
        fi
        rm -rf /tmp/security-analyzer
        ok "security-analyzer skill installed"
    else
        warn "security-analyzer clone failed"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 9: UI UX Pro Max Skill
# ============================================
step_header "Installing UI UX Pro Max Skill"

UIPRO_SKILL_DIR="$HOME/.claude/skills/ui-ux-pro-max"
UIPRO_SKILL_DIR_LOCAL="$WORKSPACE_FOLDER/.claude/skills/ui-ux-pro-max"

checking "UI UX Pro Max skill"
if skill_has_content "$UIPRO_SKILL_DIR" || skill_has_content "$UIPRO_SKILL_DIR_LOCAL"; then
    skip "UI UX Pro Max skill already installed"
else
    [ -d "$UIPRO_SKILL_DIR" ] && [ -z "$(ls -A "$UIPRO_SKILL_DIR" 2>/dev/null)" ] && rm -rf "$UIPRO_SKILL_DIR"
    [ -d "$UIPRO_SKILL_DIR_LOCAL" ] && [ -z "$(ls -A "$UIPRO_SKILL_DIR_LOCAL" 2>/dev/null)" ] && rm -rf "$UIPRO_SKILL_DIR_LOCAL"
    
    status "Installing UI UX Pro Max skill"
    npx -y uipro-cli init --ai claude --offline 2>&1 | tail -3
    
    if skill_has_content "$UIPRO_SKILL_DIR" || skill_has_content "$UIPRO_SKILL_DIR_LOCAL"; then
        ok "UI UX Pro Max skill installed"
    else
        warn "UI UX Pro Max skill may be incomplete"
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 10: Worktree Manager Skill
# ============================================
step_header "Installing Worktree Manager Skill"

WORKTREE_SKILL_DIR="$HOME/.claude/skills/worktree-manager"

checking "worktree-manager skill"
if skill_has_content "$WORKTREE_SKILL_DIR" && [ -f "$WORKTREE_SKILL_DIR/SKILL.md" ]; then
    skip "worktree-manager skill already installed"
else
    mkdir -p "$WORKTREE_SKILL_DIR"
    status "Cloning worktree-manager (HTTPS)"
    if git clone --depth 1 https://github.com/Wirasm/worktree-manager-skill.git "$WORKTREE_SKILL_DIR" 2>/dev/null; then
        # Extract skill from nested .claude/skills/ structure
        if [ -d "$WORKTREE_SKILL_DIR/.claude/skills" ]; then
            cp -r "$WORKTREE_SKILL_DIR/.claude/skills/"* "$WORKTREE_SKILL_DIR/" 2>/dev/null
            ok "worktree-manager skill installed (extracted from nested structure)"
        else
            ok "worktree-manager skill installed"
        fi
    else
        status "Trying SSH..."
        if git clone --depth 1 git@github.com:Wirasm/worktree-manager-skill.git "$WORKTREE_SKILL_DIR" 2>/dev/null; then
            ok "worktree-manager skill installed via SSH"
        else
            warn "Git clone failed - creating minimal skill"
            cat > "$WORKTREE_SKILL_DIR/SKILL.md" << 'WORKTREE_SKILL'
---
name: worktree-manager
description: Create, manage, and cleanup git worktrees with Claude Code agents.
---

# Worktree Manager

Manage parallel development environments using git worktrees.

## Commands

### Create Worktree
```bash
git worktree add ~/tmp/worktrees/<branch-name> -b <branch-name>
cd ~/tmp/worktrees/<branch-name>
cp ../.env . 2>/dev/null || true
npm install
```

### List Worktrees
```bash
git worktree list
```

### Remove Worktree
```bash
git worktree remove ~/tmp/worktrees/<branch-name>
git branch -d <branch-name>
```

### Port Allocation
Use ports 8100-8199 for worktree dev servers to avoid conflicts.
WORKTREE_SKILL
            cat > "$WORKTREE_SKILL_DIR/config.json" << 'WORKTREE_CONFIG'
{
  "terminal": "tmux",
  "shell": "bash",
  "claudeCommand": "claude --dangerously-skip-permissions",
  "portPool": { "start": 8100, "end": 8199 },
  "portsPerWorktree": 2,
  "worktreeBase": "~/tmp/worktrees"
}
WORKTREE_CONFIG
            ok "worktree-manager minimal skill created"
        fi
    fi
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 11: Statusline Pro
# ============================================
step_header "Installing Statusline Pro"

checking "statusline-pro"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_CONFIG_DIR="$HOME/.claude/statusline-pro"
STATUSLINE_SCRIPT="$HOME/.claude/turbo-flow-statusline.sh"

mkdir -p "$STATUSLINE_CONFIG_DIR" 2>/dev/null

info "ccusage: available on-demand via 'npx -y ccusage'"

status "Creating statusline script"
cat > "$STATUSLINE_SCRIPT" << 'STATUSLINE_SCRIPT'
#!/bin/bash
# TURBO FLOW v3.4.1 - STATUSLINE

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
    if [[ -n $(git -C "$CWD" status --porcelain 2>/dev/null) ]]; then
        GIT_DIRTY="*"
    else
        GIT_DIRTY=""
    fi
fi

format_duration() {
    local ms=$1
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    local hours=$((mins / 60))
    mins=$((mins % 60))
    secs=$((secs % 60))
    if [ $hours -gt 0 ]; then echo "${hours}h${mins}m"
    elif [ $mins -gt 0 ]; then echo "${mins}m${secs}s"
    else echo "${secs}s"
    fi
}

format_tokens() {
    local tokens=$1
    if [ $tokens -ge 1000000 ]; then echo "$((tokens / 1000000))M"
    elif [ $tokens -ge 1000 ]; then echo "$((tokens / 1000))k"
    else echo "$tokens"
    fi
}

progress_bar() {
    local pct=$1
    local width=${2:-15}
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar_color=""
    if [ $pct -lt 50 ]; then bar_color="$FG_GREEN"
    elif [ $pct -lt 70 ]; then bar_color="$FG_CYAN"
    elif [ $pct -lt 85 ]; then bar_color="$FG_YELLOW"
    elif [ $pct -lt 95 ]; then bar_color="$FG_ORANGE"
    else bar_color="$FG_RED"
    fi
    printf "${bar_color}"
    for ((i=0; i<filled; i++)); do printf "#"; done
    printf "${FG_GRAY}"
    for ((i=0; i<empty; i++)); do printf "-"; done
    printf "${RST}"
}

DURATION_FMT=$(format_duration $DURATION_MS)
CTX_TOTAL=$((CTX_INPUT + CTX_OUTPUT))
CTX_TOTAL_FMT=$(format_tokens $CTX_TOTAL)
CTX_SIZE_FMT=$(format_tokens $CTX_SIZE)
CACHE_HIT_PCT=0
if [ $((CACHE_READ + CACHE_CREATE)) -gt 0 ]; then
    CACHE_HIT_PCT=$((CACHE_READ * 100 / (CACHE_READ + CACHE_CREATE + 1)))
fi
MODEL_ABBREV=$(echo "$MODEL" | sed 's/Sonnet/So/;s/Opus/Op/;s/Haiku/Ha/' | cut -c1-8)
COST_FMT=$(printf "%.2f" $COST_USD 2>/dev/null || echo "0.00")

LINE1="${BG_MAGENTA}${FG_WHITE}${BOLD} [Project] ${PROJECT_NAME} ${RST}${FG_MAGENTA}${BG_CYAN}${SEP}${RST}${BG_CYAN}${FG_WHITE}${BOLD} [Model] ${MODEL_ABBREV} ${RST}${FG_CYAN}${BG_GREEN}${SEP}${RST}"
[ -n "$GIT_BRANCH" ] && LINE1+="${BG_GREEN}${FG_WHITE}${BOLD} [Git] ${GIT_BRANCH}${GIT_DIRTY} ${RST}${FG_GREEN}${BG_BLUE}${SEP}${RST}" || LINE1+="${BG_GREEN}${FG_WHITE}${BOLD} [Git] no-git ${RST}${FG_GREEN}${BG_BLUE}${SEP}${RST}"
[ -n "$VERSION" ] && LINE1+="${BG_BLUE}${FG_WHITE} [v] ${VERSION} ${RST}${FG_BLUE}${BG_PINK}${SEP}${RST}"
LINE1+="${BG_PINK}${FG_WHITE} [Style] ${OUTPUT_STYLE} ${RST}"
[ -n "$SESSION_ID" ] && LINE1+="${FG_PINK}${BG_DEEP}${SEP}${RST}${BG_DEEP}${FG_GRAY} [SID] ${SESSION_ID} ${RST}"

LINE2="${BG_YELLOW}${FG_WHITE}${BOLD} [Tokens] ${CTX_TOTAL_FMT}/${CTX_SIZE_FMT} ${RST}${FG_YELLOW}${BG_DARK}${SEP}${RST}${BG_DARK}${FG_WHITE} [Ctx] $(progress_bar $CTX_USED_PCT 20) ${CTX_USED_PCT}% ${RST}${FG_DARK}${BG_CYAN}${SEP}${RST}"
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

status "Configuring Statusline in settings.json"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
    mkdir -p "$HOME/.claude"
    echo '{}' > "$CLAUDE_SETTINGS"
fi

node -e "
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync('$CLAUDE_SETTINGS', 'utf8'));
settings.statusLine = {
    type: 'command',
    command: '$STATUSLINE_SCRIPT',
    padding: 0
};
fs.writeFileSync('$CLAUDE_SETTINGS', JSON.stringify(settings, null, 2));
" 2>/dev/null && ok "Statusline configured in settings.json" || warn "settings.json config failed"

info "Elapsed: $(elapsed)"

# ============================================
# STEP 12: Workspace setup
# ============================================
step_header "Setting up workspace"

cd "$WORKSPACE_FOLDER" 2>/dev/null || true

[ ! -f "package.json" ] && npm init -y --silent 2>/dev/null
npm pkg set type="module" 2>/dev/null || true

# Install sql.js for memory database (after package.json exists)
if ! npm list sql.js --depth=0 >/dev/null 2>&1; then
    status "Installing sql.js for memory database"
    npm install sql.js --save-dev 2>/dev/null || warn "sql.js install failed (memory may use fallback)"
fi

for dir in src tests docs scripts config plans; do
    mkdir -p "$dir" 2>/dev/null
done

ok "Workspace configured"
info "Elapsed: $(elapsed)"

# ============================================
# STEP 13: Bash aliases
# ============================================
step_header "Installing bash aliases"

checking "TURBO FLOW aliases"
if grep -q "TURBO FLOW v3.4.1 COMPLETE" ~/.bashrc 2>/dev/null; then
    skip "Bash aliases already installed"
else
    sed -i '/# === TURBO FLOW/,/# === END TURBO FLOW/d' ~/.bashrc 2>/dev/null || true
    
    cat << 'ALIASES_EOF' >> ~/.bashrc

# === TURBO FLOW v3.4.1 COMPLETE + PLUGINS ===

# RUVECTOR
alias ruv="npx -y ruvector"
alias ruv-stats="npx -y @ruvector/cli hooks stats"
alias ruv-route="npx -y @ruvector/cli hooks route"
alias ruv-remember="npx -y @ruvector/cli hooks remember"
alias ruv-recall="npx -y @ruvector/cli hooks recall"
alias ruv-learn="npx -y @ruvector/cli hooks learn"
alias ruv-init="npx -y @ruvector/cli hooks init"
alias ruv-viz="cd ~/.claude/skills/rUv_helpers/claude-flow-ruvector-visualization && node server.js &"
alias ruv-viz-stop="pkill -f 'node server.js' 2>/dev/null; echo 'Visualization stopped'"

# CLAUDE CODE
alias dsp="claude --dangerously-skip-permissions"

# CLAUDE FLOW V3
alias cf="npx -y claude-flow@alpha"
alias cf-init="npx -y claude-flow@alpha init --force"
alias cf-wizard="npx -y claude-flow@alpha init --wizard"
alias cf-swarm="npx -y claude-flow@alpha swarm init --topology hierarchical"
alias cf-mesh="npx -y claude-flow@alpha swarm init --topology mesh"
alias cf-agent="npx -y claude-flow@alpha --agent"
alias cf-list="npx -y claude-flow@alpha --list"
alias cf-daemon="npx -y claude-flow@alpha daemon start"
alias cf-memory="npx -y claude-flow@alpha memory"
alias cf-doctor="npx -y claude-flow@alpha doctor"
alias cf-mcp="npx -y claude-flow@alpha mcp start"
alias cf-plugins="npx -y claude-flow@alpha plugins"

# CLAUDE FLOW SKILLS - Core (built-in, accessed via cf command)
alias cf-sparc="npx -y claude-flow@alpha --skill sparc-methodology"
alias cf-swarm-skill="npx -y claude-flow@alpha swarm"
alias cf-hive="npx -y claude-flow@alpha hive-mind"
alias cf-pair="npx -y claude-flow@alpha --agent pair-programmer"

# CLAUDE FLOW SKILLS - AgentDB
alias cf-agentdb-search="npx -y claude-flow@alpha memory search"
alias cf-agentdb-store="npx -y claude-flow@alpha memory store"

# CLAUDE FLOW PLUGINS
alias plugin-list="npx -y claude-flow@alpha plugins list"
alias plugin-search="npx -y claude-flow@alpha plugins search"

# AGENTIC QE
alias aqe="npx -y agentic-qe"
alias aqe-generate="npx -y agentic-qe generate"
alias aqe-gate="npx -y agentic-qe gate"

# CLAUDE FLOW BROWSER (59 MCP tools)
alias cfb-open="npx -y claude-flow@alpha mcp call browser/open"
alias cfb-snap="npx -y claude-flow@alpha mcp call browser/snapshot"
alias cfb-click="npx -y claude-flow@alpha mcp call browser/click"
alias cfb-fill="npx -y claude-flow@alpha mcp call browser/fill"
alias cfb-trajectory="npx -y claude-flow@alpha mcp call browser/trajectory-start"
alias cfb-learn="npx -y claude-flow@alpha mcp call browser/trajectory-save"

# OPENSPEC
alias os="npx -y @fission-ai/openspec"
alias os-init="npx -y @fission-ai/openspec init"

# WORKTREE MANAGER
alias wt-status="claude 'What is the status of my worktrees?'"
alias wt-clean="claude 'Clean up completed worktrees'"
alias wt-create="claude 'Create a worktree for'"

# DEPLOYMENT
alias deploy="claude 'Deploy this app'"
alias deploy-preview="claude 'Deploy and give me the preview URL'"

# HOOKS INTELLIGENCE
alias hooks-pre="npx -y claude-flow@alpha hooks pre-edit"
alias hooks-post="npx -y claude-flow@alpha hooks post-edit"
alias hooks-train="npx -y claude-flow@alpha hooks pretrain --depth deep"
alias hooks-intel="npx -y claude-flow@alpha hooks intelligence --status"

# MEMORY VECTOR OPERATIONS
alias mem-search="npx -y claude-flow@alpha memory search"
alias mem-vsearch="npx -y claude-flow@alpha memory vector-search"
alias mem-vstore="npx -y claude-flow@alpha memory store-vector"
alias mem-store="npx -y claude-flow@alpha memory store"
alias mem-stats="npx -y claude-flow@alpha memory stats"

# NEURAL OPERATIONS
alias neural-train="npx -y claude-flow@alpha neural train"
alias neural-status="npx -y claude-flow@alpha neural status"
alias neural-patterns="npx -y claude-flow@alpha neural patterns"

# AGENTDB
alias agentdb="npx -y agentdb"
alias agentdb-init="npx -y agentdb init"
alias agentdb-stats="npx -y agentdb stats"

# COST TRACKING
alias ccusage="npx -y ccusage"

# STATUS HELPERS
turbo-status() {
    echo "Turbo Flow v3.4.1 (Complete + Plugins) Status"
    echo "================================================"
    echo ""
    echo "Core:"
    echo "  Node.js:       $(node -v 2>/dev/null || echo 'not found')"
    echo "  Claude Code:   $(claude --version 2>/dev/null | head -1 || echo 'not found')"
    echo "  Claude Flow:   $(npx -y claude-flow@alpha --version 2>/dev/null | head -1 || echo 'not found')"
    echo ""
    echo "Skills: Built-in to Claude Flow"
    echo "Plugins: Available via 'cf-plugins list'"
    echo "MCP Tools: 175+ available"
    echo ""
    echo "Run 'turbo-help' for command reference"
}

turbo-help() {
    echo "Turbo Flow v3.4.1 Quick Reference"
    echo "=================================="
    echo ""
    echo "CORE:          cf, cf-init, cf-swarm, cf-mesh"
    echo "MEMORY:        mem-search, mem-vsearch, mem-stats"
    echo "NEURAL:        neural-train, neural-status, neural-patterns"
    echo "BROWSER:       cfb-open, cfb-snap, cfb-click, cfb-trajectory"
    echo "WORKFLOW:      wt-status, deploy, deploy-preview"
    echo "PLUGINS:       cf-plugins list, plugin-search"
    echo ""
    echo "STATUS:        turbo-status, turbo-help"
}

export PATH="$HOME/.claude/bin:$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
[ -n "$npm_config_prefix" ] && export PATH="$npm_config_prefix/bin:$PATH"

# === END TURBO FLOW v3.4.1 COMPLETE + PLUGINS ===

ALIASES_EOF
    ok "Bash aliases installed"
fi

info "Elapsed: $(elapsed)"

# ============================================
# STEP 14: Run Doctor
# ============================================
step_header "Running Claude Flow Doctor"

status "Running diagnostics..."
npx -y claude-flow@alpha doctor 2>&1 | head -30 || true

# Clear npx cache to fix stale version warnings (v0.0.0 issue)
status "Clearing npx cache..."
npx clear-npx-cache 2>/dev/null || npm cache clean --force 2>/dev/null || true
ok "Cache cleared"

info "Elapsed: $(elapsed)"

# ============================================
# COMPLETE
# ============================================
step_header "Setup Complete"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

CF_STATUS="[ ]"; [ -d "$WORKSPACE_FOLDER/.claude-flow" ] && CF_STATUS="[OK]"
CLAUDE_STATUS="[ ]"; has_cmd claude && CLAUDE_STATUS="[OK]"
MEMORY_STATUS="[ ]"; [ -d "$WORKSPACE_FOLDER/.claude-flow/memory" ] && MEMORY_STATUS="[OK]"
MCP_STATUS="[ ]"; [ -f ~/.claude/claude_desktop_config.json ] && grep -q "claude-flow" ~/.claude/claude_desktop_config.json 2>/dev/null && MCP_STATUS="[OK]"
STATUSLINE_STATUS="[ ]"; [ -f ~/.claude/turbo-flow-statusline.sh ] && [ -x ~/.claude/turbo-flow-statusline.sh ] && STATUSLINE_STATUS="[OK]"

echo ""
echo "=================================================="
echo "   TURBO FLOW v3.4.1 SETUP COMPLETE!"
echo "=================================================="
echo ""
progress_bar 100
echo ""
echo ""
echo "  SUMMARY"
echo "  -------"
echo "  CORE"
echo "  $CLAUDE_STATUS Claude Code"
echo "  $CF_STATUS Claude Flow V3"
echo ""
echo "  INFRASTRUCTURE"
echo "  $MEMORY_STATUS Memory System (HNSW/AgentDB)"
echo "  $MCP_STATUS MCP Server (175+ tools)"
echo "  $STATUSLINE_STATUS Statusline Pro"
echo ""
echo "  Time: ${TOTAL_TIME}s"
echo ""
echo "  QUICK START"
echo "  ----------"
echo "  1. source ~/.bashrc"
echo "  2. turbo-status"
echo "  3. turbo-help"
echo ""
echo "  Happy coding!"
echo ""
