#!/usr/bin/env bash
# =============================================================================
# Turbo Flow — Ruv Stack Edition (v4.1.0) installer
#
# Pure add-on. Does NOT modify devpods/setup.sh, .mcp.json, or any file the
# v4.0 installer owns. Safe to run (or skip) independently, any number of
# times, on top of an existing Turbo Flow v4.0 install.
#
# Installs the dev-relevant slice of the ruv stack (see docs/RUV-STACK.md):
#   - RuVector (deepened): the optional `npm install ruvector` already
#     documented in AGENTDB-VS-RUVECTOR.md but not installed by default
#   - ruVLLM: local/offline sparse-attention model-routing tier
#   - MetaHarness: per-repo branded agent-harness generator
#   - Skygraph: optional, off by default (--with-skygraph)
#
# Explicitly OUT of scope (see docs/RUV-STACK.md for why): RuView, rUv Neural,
# PhotonLayer (no public repo exists under ruvnet as of this script's writing).
#
# Usage:
#   ./scripts/setup-ruv-stack.sh                    # dry run — prints the plan, changes nothing
#   ./scripts/setup-ruv-stack.sh --apply             # actually install
#   ./scripts/setup-ruv-stack.sh --apply --with-skygraph
# =============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE="${WORKSPACE:-$(pwd)}"
LOG="/tmp/turboflow-ruv-stack-setup.log"
START_TIME=$(date +%s)

APPLY=0
WITH_SKYGRAPH=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --with-skygraph) WITH_SKYGRAPH=1 ;;
        -h|--help)
            echo "Usage: $0 [--apply] [--with-skygraph]"
            echo "  (no flags)       dry run — print the plan, change nothing"
            echo "  --apply          actually install"
            echo "  --with-skygraph  also clone the optional Skygraph demo"
            exit 0
            ;;
        *) echo "Unknown flag: $arg (see --help)"; exit 1 ;;
    esac
done

step() { echo -e "\n${CYAN}━━━ [$1/4] $2 ━━━${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
plan() { echo -e "  ${CYAN}→ would run:${NC} $1"; }
elapsed() { echo "$(($(date +%s) - START_TIME))s"; }

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Turbo Flow — Ruv Stack Edition (v4.1.0)        ║"
echo "║   RuVector+ · ruVLLM · MetaHarness · (Skygraph)  ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ "$APPLY" -eq 0 ]; then
    echo -e "${YELLOW}DRY RUN — no changes will be made. Pass --apply to install.${NC}\n"
fi

run() {
    # run <description> <command...>
    local desc="$1"; shift
    if [ "$APPLY" -eq 0 ]; then
        plan "$*"
        return 0
    fi
    if "$@" >> "$LOG" 2>&1; then
        ok "$desc"
        return 0
    else
        warn "$desc failed (see $LOG)"
        return 1
    fi
}

# =============================================================================
# STEP 1: RuVector (deepened) — the optional npm install AGENTDB-VS-RUVECTOR.md
# already documents but leaves undone by default. See that file for the full
# AgentDB-vs-RuVector tradeoff; this step is just the "add it" action.
# =============================================================================
step 1 "RuVector (deepened)"

if ! command -v npm &>/dev/null; then
    warn "npm not found — skipping RuVector (Node.js required)"
else
    run "ruvector installed" npm install ruvector --prefix "$WORKSPACE"
fi
ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 2: ruVLLM — local/offline model-routing tier
# =============================================================================
step 2 "ruVLLM (local model tier)"

if ! command -v cargo &>/dev/null; then
    warn "cargo not found — skipping ruvllm (Rust toolchain required: https://rustup.rs)"
else
    run "ruvllm installed" cargo install ruvllm
    run "ruvllm-esp32 (edge variant) added" cargo add ruvllm-esp32 --manifest-path "${WORKSPACE}/Cargo.toml" 2>/dev/null || \
        warn "ruvllm-esp32 skipped (no Cargo.toml, or edge target not needed — optional)"
fi
ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 3: MetaHarness — per-repo branded agent-harness generator
# =============================================================================
step 3 "MetaHarness"

if ! command -v npx &>/dev/null; then
    warn "npx not found — skipping MetaHarness (Node.js required)"
else
    if [ "$APPLY" -eq 1 ]; then
        ok "MetaHarness available via 'npx metaharness' (no persistent install needed — it's a run-on-demand generator)"
    else
        plan "npx metaharness  # run on demand per repo, nothing to pre-install"
    fi
fi
ok "Elapsed: $(elapsed)"

# =============================================================================
# STEP 4: Skygraph (optional, off by default)
# =============================================================================
step 4 "Skygraph (optional)"

if [ "$WITH_SKYGRAPH" -eq 0 ]; then
    ok "Skipped (pass --with-skygraph to include — it's a standalone browser demo, unrelated to the core dev flow)"
else
    SKYGRAPH_DIR="$WORKSPACE/.ruv-stack/skygraph"
    if [ -d "$SKYGRAPH_DIR" ]; then
        ok "Skygraph already cloned at $SKYGRAPH_DIR"
    else
        run "Skygraph cloned to $SKYGRAPH_DIR" git clone --depth 1 https://github.com/ruvnet/skygraph "$SKYGRAPH_DIR"
    fi
fi
ok "Elapsed: $(elapsed)"

# =============================================================================
# Aliases (rv-*) — separate file, sourced alongside ~/.turboflow_aliases
# =============================================================================
if [ "$APPLY" -eq 1 ]; then
    RUV_ALIAS_FILE="$HOME/.turboflow_ruv_aliases"
    cat > "$RUV_ALIAS_FILE" << 'RUVALIASEOF'
# =============================================================================
# Turbo Flow — Ruv Stack Edition aliases (rv-*)
# Additive only — never overrides rf-*, bd-*, wt-*, gnx-*, aqe-*, os-*, etc.
# =============================================================================

# --- RuVector (deepened) ---
alias rv-vector-init='npm install ruvector'

# --- ruVLLM (local model tier) ---
alias rv-llm-serve='ruvllm serve'
rv-llm-route() {
    # Usage: rv-llm-route "<task description>"
    echo "Routing to local ruVLLM tier (offline, \$0): $1"
    ruvllm route --task "$1"
}

# --- MetaHarness ---
alias rv-harness-gen='npx metaharness'

# --- Skygraph (optional demo, only meaningful if installed with --with-skygraph) ---
rv-sky-demo() {
    local dir="${WORKSPACE:-$(pwd)}/.ruv-stack/skygraph/docs"
    if [ -d "$dir" ]; then
        (cd "$dir" && python3 -m http.server 8000)
    else
        echo "Skygraph not installed. Run: ./scripts/setup-ruv-stack.sh --apply --with-skygraph"
    fi
}
RUVALIASEOF

    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            grep -q 'turboflow_ruv_aliases' "$rc" 2>/dev/null || \
                echo "[ -f \"$RUV_ALIAS_FILE\" ] && source \"$RUV_ALIAS_FILE\"" >> "$rc"
        fi
    done
    source "$RUV_ALIAS_FILE" 2>/dev/null || true
    ok "rv-* aliases written to $RUV_ALIAS_FILE and sourced"
else
    plan "write rv-* aliases to ~/.turboflow_ruv_aliases and source from ~/.bashrc / ~/.zshrc"
fi

echo ""
if [ "$APPLY" -eq 0 ]; then
    echo -e "${YELLOW}Dry run complete in $(elapsed). Re-run with --apply to install.${NC}"
else
    echo -e "${GREEN}Ruv Stack Edition installed in $(elapsed).${NC}"
    echo "See docs/RUV-STACK.md for what each piece does and why RuView / rUv Neural / PhotonLayer are excluded."
fi
