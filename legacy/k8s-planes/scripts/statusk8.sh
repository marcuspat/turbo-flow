#!/bin/bash
# =============================================================================
# DevPod Cluster Status Dashboard
# Usage: ./status.sh              (full dashboard)
#        ./status.sh --watch      (auto-refresh every 15s)
#        ./status.sh --quick      (pods + resources only)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_FILE="$SCRIPT_DIR/devpod-kubeconfig.yaml"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Validate ---
if [ ! -f "$KUBE_FILE" ]; then
    echo -e "${RED}❌ devpod-kubeconfig.yaml not found in $SCRIPT_DIR${NC}"
    exit 1
fi
export KUBECONFIG="$KUBE_FILE"

# --- Helper ---
divider() {
    echo -e "${DIM}────────────────────────────────────────────────────────────────${NC}"
}

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    divider
}

# --- Watch mode ---
if [ "$1" == "--watch" ]; then
    INTERVAL="${2:-15}"
    echo -e "${BOLD}${CYAN}👁️  Watch mode — refreshing every ${INTERVAL}s (Ctrl+C to stop)${NC}"
    while true; do
        clear
        "$0" --quick
        echo ""
        echo -e "${DIM}Last refresh: $(date '+%H:%M:%S') — next in ${INTERVAL}s${NC}"
        sleep "$INTERVAL"
    done
    exit 0
fi

# =============================================================================
# CLUSTER CONNECTION
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║            DevPod Cluster Status Dashboard                  ║${NC}"
echo -e "${BOLD}${CYAN}║            $(date '+%Y-%m-%d %H:%M:%S')                              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}❌ CLUSTER UNREACHABLE — cannot connect to Rackspace${NC}"
    echo -e "${YELLOW}💡 Run: source kubeconfig.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Connected: $(kubectl config current-context)${NC}"

# =============================================================================
# NODES
# =============================================================================
print_header "🖥️  NODES"

NODE_DATA=$(kubectl get nodes -o json 2>/dev/null)
NODE_COUNT=$(echo "$NODE_DATA" | jq '.items | length')

for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_NAME=$(echo "$NODE_DATA" | jq -r ".items[$i].metadata.name")
    NODE_STATUS=$(echo "$NODE_DATA" | jq -r ".items[$i].status.conditions[] | select(.type==\"Ready\") | .status")
    NODE_AGE_TS=$(echo "$NODE_DATA" | jq -r ".items[$i].metadata.creationTimestamp")

    # Calculate age
    if command -v gdate &>/dev/null; then
        CREATED=$(gdate -d "$NODE_AGE_TS" +%s 2>/dev/null)
    else
        CREATED=$(date -d "$NODE_AGE_TS" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$NODE_AGE_TS" +%s 2>/dev/null)
    fi
    NOW=$(date +%s)
    if [ -n "$CREATED" ]; then
        AGE_SECS=$((NOW - CREATED))
        AGE_DAYS=$((AGE_SECS / 86400))
        AGE_HOURS=$(( (AGE_SECS % 86400) / 3600 ))
        AGE_MINS=$(( (AGE_SECS % 3600) / 60 ))
        if [ $AGE_DAYS -gt 0 ]; then
            AGE="${AGE_DAYS}d ${AGE_HOURS}h"
        elif [ $AGE_HOURS -gt 0 ]; then
            AGE="${AGE_HOURS}h ${AGE_MINS}m"
        else
            AGE="${AGE_MINS}m"
        fi
    else
        AGE="?"
    fi

    if [ "$NODE_STATUS" == "True" ]; then
        STATUS_ICON="${GREEN}● Ready${NC}"
    else
        STATUS_ICON="${RED}● NotReady${NC}"
    fi

    echo -e "  ${BOLD}$NODE_NAME${NC}"
    echo -e "    Status: $STATUS_ICON    Age: ${AGE}    Type: Spot"

    # Resource usage from kubectl top
    TOP_LINE=$(kubectl top node "$NODE_NAME" --no-headers 2>/dev/null)
    if [ -n "$TOP_LINE" ]; then
        CPU_USED=$(echo "$TOP_LINE" | awk '{print $2}')
        CPU_PCT=$(echo "$TOP_LINE" | awk '{print $3}')
        MEM_USED=$(echo "$TOP_LINE" | awk '{print $4}')
        MEM_PCT=$(echo "$TOP_LINE" | awk '{print $5}')

        # Color code percentages
        CPU_NUM=$(echo "$CPU_PCT" | tr -d '%')
        MEM_NUM=$(echo "$MEM_PCT" | tr -d '%')

        if [ "$CPU_NUM" -gt 80 ] 2>/dev/null; then CPU_COLOR="$RED"
        elif [ "$CPU_NUM" -gt 50 ] 2>/dev/null; then CPU_COLOR="$YELLOW"
        else CPU_COLOR="$GREEN"; fi

        if [ "$MEM_NUM" -gt 80 ] 2>/dev/null; then MEM_COLOR="$RED"
        elif [ "$MEM_NUM" -gt 50 ] 2>/dev/null; then MEM_COLOR="$YELLOW"
        else MEM_COLOR="$GREEN"; fi

        echo -e "    CPU:    ${CPU_COLOR}${CPU_PCT}${NC} (${CPU_USED})    Memory: ${MEM_COLOR}${MEM_PCT}${NC} (${MEM_USED})"
    else
        echo -e "    ${DIM}(metrics not available — metrics-server may need a moment)${NC}"
    fi

    # Ephemeral storage allocation
    EPHEMERAL_REQ=$(kubectl describe node "$NODE_NAME" 2>/dev/null | grep "ephemeral-storage" | head -1 | awk '{print $2, $3}')
    if [ -n "$EPHEMERAL_REQ" ]; then
        echo -e "    Ephemeral Storage: $EPHEMERAL_REQ"
    fi

    # Pod count on this node
    POD_COUNT=$(kubectl get pods -A --field-selector "spec.nodeName=$NODE_NAME" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    Pods on node: $POD_COUNT"
    echo ""
done

# =============================================================================
# DEVPOD WORKSPACES + PODS (merged view)
# =============================================================================
print_header "🚀 DEVPOD WORKSPACES"

DEVPOD_LIST=$(devpod list --output json 2>/dev/null)

# Show workspace summary
if [ -z "$DEVPOD_LIST" ] || [ "$DEVPOD_LIST" == "null" ] || [ "$DEVPOD_LIST" == "[]" ]; then
    echo -e "  ${DIM}No workspaces registered.${NC}"
else
    WS_COUNT=$(echo "$DEVPOD_LIST" | jq 'length')
    echo -e "  ${BOLD}$WS_COUNT workspace(s) registered${NC}"
    echo ""
fi

# =============================================================================
# DEVPOD PODS (Kubernetes)
# =============================================================================
print_header "📦 DEVPOD PODS"

# Build workspace ID list from devpod list for name resolution
# Pod names follow pattern: devpod-default-{prefix}-{hash}
# where prefix = first 2 chars of the workspace id
WS_ID_LIST=""
if [ -n "$DEVPOD_LIST" ] && [ "$DEVPOD_LIST" != "null" ] && [ "$DEVPOD_LIST" != "[]" ]; then
    WS_ID_LIST=$(echo "$DEVPOD_LIST" | jq -r '.[].id' 2>/dev/null)
fi

# Also get pod labels JSON for label-based lookup
POD_LABELS_JSON=$(kubectl get pods -n devpod -o json 2>/dev/null)

# Helper: resolve workspace name from pod name
resolve_workspace() {
    local pod_name="$1"
    local ws_name=""

    # Try label lookup first (most reliable)
    if [ -n "$POD_LABELS_JSON" ]; then
        ws_name=$(echo "$POD_LABELS_JSON" | jq -r ".items[] | select(.metadata.name==\"$pod_name\") | .metadata.labels[\"devpod.sh/id\"] // .metadata.labels[\"devpod.sh/workspace\"] // \"\"" 2>/dev/null)
    fi

    # Fall back to prefix matching from devpod list
    if [ -z "$ws_name" ]; then
        local pod_prefix
        pod_prefix=$(echo "$pod_name" | sed -n 's/^devpod-default-\([a-z0-9]*\)-[a-f0-9]*$/\1/p')
        if [ -n "$pod_prefix" ] && [ -n "$WS_ID_LIST" ]; then
            while IFS= read -r ws_id; do
                local id_prefix
                id_prefix=$(echo "$ws_id" | cut -c1-2)
                if [ "$pod_prefix" == "$id_prefix" ]; then
                    ws_name="$ws_id"
                    break
                fi
            done <<< "$WS_ID_LIST"
        fi
    fi

    echo "$ws_name"
}

DEVPOD_PODS=$(kubectl get pods -n devpod --no-headers 2>/dev/null)
if [ -z "$DEVPOD_PODS" ]; then
    echo -e "  ${DIM}No pods in devpod namespace.${NC}"
else
    HEALTHY=0
    SICK=0
    GHOST=0

    while IFS= read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        POD_READY=$(echo "$line" | awk '{print $2}')
        POD_STATUS=$(echo "$line" | awk '{print $3}')
        POD_RESTARTS=$(echo "$line" | awk '{print $4}')
        POD_AGE=$(echo "$line" | awk '{print $5}')
        POD_NODE=$(echo "$line" | awk '{print $7}')

        # Resolve workspace name from pod name
        WS_NAME=$(resolve_workspace "$POD_NAME")

        # Get source repo if workspace is known
        WS_SOURCE=""
        if [ -n "$WS_NAME" ] && [ -n "$DEVPOD_LIST" ]; then
            WS_SOURCE=$(echo "$DEVPOD_LIST" | jq -r ".[] | select(.id==\"$WS_NAME\") | .source.gitRepository // .source.localFolder // \"\"" 2>/dev/null | sed 's|https://github.com/||')
        fi

        # Display name
        if [ -n "$WS_NAME" ]; then
            DISPLAY_NAME="${BOLD}${WS_NAME}${NC}  ${DIM}(${POD_NAME})${NC}"
        else
            DISPLAY_NAME="${BOLD}${POD_NAME}${NC}"
        fi

        case "$POD_STATUS" in
            Running)
                if [ "$POD_READY" == "1/1" ]; then
                    ICON="${GREEN}✅${NC}"
                    ((HEALTHY++))
                else
                    ICON="${YELLOW}⏳${NC}"
                    ((SICK++))
                fi
                ;;
            ContainerStatusUnknown|Unknown|Evicted)
                ICON="${RED}👻${NC}"
                ((GHOST++))
                ;;
            ContainerCreating|PodInitializing)
                ICON="${BLUE}🔨${NC}"
                ((SICK++))
                ;;
            *)
                ICON="${RED}❌${NC}"
                ((SICK++))
                ;;
        esac

        echo -e "  $ICON  $DISPLAY_NAME"
        [ -n "$WS_SOURCE" ] && echo -e "      Repo: ${DIM}$WS_SOURCE${NC}"
        echo -e "      Status: $POD_STATUS ($POD_READY)    Restarts: $POD_RESTARTS    Age: $POD_AGE"

        # Show resource usage for running pods
        if [ "$POD_STATUS" == "Running" ]; then
            POD_TOP=$(kubectl top pod "$POD_NAME" -n devpod --no-headers 2>/dev/null)
            if [ -n "$POD_TOP" ]; then
                POD_CPU=$(echo "$POD_TOP" | awk '{print $2}')
                POD_MEM=$(echo "$POD_TOP" | awk '{print $3}')
                echo -e "      CPU: $POD_CPU    Memory: $POD_MEM"
            fi
        fi
        echo ""
    done <<< "$DEVPOD_PODS"

    # Summary line
    echo -e "  ${GREEN}$HEALTHY healthy${NC} | ${YELLOW}$SICK pending/unhealthy${NC} | ${RED}$GHOST ghost/evicted${NC}"

    if [ $GHOST -gt 0 ]; then
        echo ""
        echo -e "  ${RED}⚠️  Ghost pods detected! Clean up with:${NC}"
        echo -e "  ${DIM}kubectl get pods -n devpod | grep -E 'Unknown|Evicted' | awk '{print \$1}' | xargs kubectl delete pod -n devpod --force --grace-period=0${NC}"
    fi
fi

# =============================================================================
# PVC STATUS
# =============================================================================
print_header "💾 PERSISTENT VOLUMES"

PVC_DATA=$(kubectl get pvc -n devpod --no-headers 2>/dev/null)
if [ -z "$PVC_DATA" ]; then
    echo -e "  ${DIM}No PVCs in devpod namespace.${NC}"
else
    while IFS= read -r line; do
        PVC_NAME=$(echo "$line" | awk '{print $1}')
        PVC_STATUS=$(echo "$line" | awk '{print $2}')
        PVC_SIZE=$(echo "$line" | awk '{print $4}')

        if [ "$PVC_STATUS" == "Bound" ]; then
            ICON="${GREEN}●${NC}"
        elif [ "$PVC_STATUS" == "Terminating" ]; then
            ICON="${RED}●${NC}"
        else
            ICON="${YELLOW}●${NC}"
        fi

        echo -e "  $ICON  $PVC_NAME — $PVC_STATUS — $PVC_SIZE"
    done <<< "$PVC_DATA"
fi

# =============================================================================
# RECENT EVENTS (warnings only)
# =============================================================================
if [ "$1" != "--quick" ]; then
    print_header "⚡ RECENT WARNINGS (last 30 min)"

    EVENTS=$(kubectl get events -n devpod --sort-by='.lastTimestamp' --field-selector type=Warning 2>/dev/null | tail -10)
    if [ -z "$EVENTS" ] || [ "$EVENTS" == "No resources found in devpod namespace." ]; then
        echo -e "  ${GREEN}✅ No warnings. Cluster is clean.${NC}"
    else
        echo "$EVENTS" | while IFS= read -r line; do
            # Highlight eviction events
            if echo "$line" | grep -qi "evict"; then
                echo -e "  ${RED}$line${NC}"
            else
                echo -e "  ${YELLOW}$line${NC}"
            fi
        done
    fi

    # =============================================================================
    # PROVIDER CONFIG SUMMARY
    # =============================================================================
    print_header "⚙️  PROVIDER CONFIG"

    # Pull key settings
    PROVIDER_JSON=$(devpod provider options kubernetes --output json 2>/dev/null)
    if [ -n "$PROVIDER_JSON" ]; then
        RESOURCES=$(echo "$PROVIDER_JSON" | jq -r '.RESOURCES.value // "not set"' 2>/dev/null)
        DISK=$(echo "$PROVIDER_JSON" | jq -r '.DISK_SIZE.value // "not set"' 2>/dev/null)
        TIMEOUT=$(echo "$PROVIDER_JSON" | jq -r '.INACTIVITY_TIMEOUT.value // "none (always-on)"' 2>/dev/null)
        POD_TO=$(echo "$PROVIDER_JSON" | jq -r '.POD_TIMEOUT.value // "not set"' 2>/dev/null)

        [ -z "$TIMEOUT" ] && TIMEOUT="none (always-on)"

        echo -e "  Resources:           $RESOURCES"
        echo -e "  Disk Size:           $DISK"
        echo -e "  Inactivity Timeout:  $TIMEOUT"
        echo -e "  Pod Startup Timeout: $POD_TO"
    else
        # Fallback: not json output
        echo -e "  ${DIM}(run 'devpod provider options kubernetes' for full config)${NC}"
    fi
fi

# =============================================================================
# QUICK HEALTH SCORE
# =============================================================================
echo ""
divider
TOTAL_ISSUES=0

# Check nodes
NOT_READY=$(echo "$NODE_DATA" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))] | length')
[ "$NOT_READY" -gt 0 ] && ((TOTAL_ISSUES += NOT_READY))

# Check ghost pods
[ "$GHOST" -gt 0 ] 2>/dev/null && ((TOTAL_ISSUES += GHOST))

# Check stuck PVCs
STUCK_PVC=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c "Terminating" 2>/dev/null || true)
STUCK_PVC=${STUCK_PVC:-0}
[ "$STUCK_PVC" -gt 0 ] 2>/dev/null && ((TOTAL_ISSUES += STUCK_PVC))

# Check unbound PVCs
UNBOUND_PVC=$(kubectl get pvc -n devpod --no-headers 2>/dev/null | grep -vc "Bound" 2>/dev/null || true)
UNBOUND_PVC=${UNBOUND_PVC:-0}
[ "$UNBOUND_PVC" -gt 0 ] 2>/dev/null && ((TOTAL_ISSUES += UNBOUND_PVC))

if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✅ CLUSTER HEALTH: ALL GOOD${NC}"
else
    echo -e "${RED}${BOLD}  ⚠️  CLUSTER HEALTH: $TOTAL_ISSUES ISSUE(S) DETECTED${NC}"
    [ "$NOT_READY" -gt 0 ] && echo -e "     ${RED}• $NOT_READY node(s) not ready${NC}"
    [ "$GHOST" -gt 0 ] 2>/dev/null && echo -e "     ${RED}• $GHOST ghost pod(s) — need cleanup${NC}"
    [ "$STUCK_PVC" -gt 0 ] 2>/dev/null && echo -e "     ${RED}• $STUCK_PVC stuck PVC(s)${NC}"
    [ "$UNBOUND_PVC" -gt 0 ] 2>/dev/null && echo -e "     ${RED}• $UNBOUND_PVC unbound PVC(s) — blocking scheduling${NC}"
fi
echo ""
