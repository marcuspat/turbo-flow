#!/bin/bash
# --- CONFIGURATION ---
KUBE_FILE="$(pwd)/devpod-kubeconfig.yaml"

echo "--------------------------------------------------------"
echo "🛠️  STEP 1: Validating Kubeconfig path..."
if [ ! -f "$KUBE_FILE" ]; then
    echo "❌ FATAL: devpod-kubeconfig.yaml not found at $KUBE_FILE"
    echo "💡 Make sure you are in the correct directory."
    exit 1
fi

export KUBECONFIG="$KUBE_FILE"
echo "✅ KUBECONFIG set to: $KUBECONFIG"

echo ""
echo "--------------------------------------------------------"
echo "🌐 STEP 2: Testing Cluster Connection..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ CONNECTION REFUSED: Cannot reach Rackspace."
    echo "⚠️  Checking for localhost error..."
    kubectl cluster-info
    exit 1
else
    echo "✅ Successfully connected to: $(kubectl config current-context)"
fi

echo ""
echo "--------------------------------------------------------"
echo "🖥️  STEP 3: Node Health & Disk Status..."
kubectl get nodes
echo "💡 Tip: If Status is 'NotReady', the Spot instance was likely reclaimed."

echo ""
echo "--------------------------------------------------------"
echo "💾 STEP 4: Checking Volumes & PVCs..."

# Check for stuck PVCs
STUCK_PVC=$(kubectl get pvc -A 2>/dev/null | grep -i "Terminating")
if [ -n "$STUCK_PVC" ]; then
    echo "⚠️  WARNING: Stuck PVCs (Terminating):"
    echo "$STUCK_PVC"
    echo ""
    echo "💡 Fix: kubectl delete pvc <name> -n devpod --force --grace-period=0"
else
    echo "✅ No stuck volumes detected."
fi

# Check for unbound PVCs (the cause of scheduling failures)
UNBOUND_PVC=$(kubectl get pvc -n devpod --no-headers 2>/dev/null | grep -v "Bound")
if [ -n "$UNBOUND_PVC" ]; then
    echo "⚠️  WARNING: Unbound PVCs detected (will block pod scheduling):"
    echo "$UNBOUND_PVC"
    echo ""
    echo "💡 Fix: kubectl delete pvc --all -n devpod --force --grace-period=0"
    echo "   Then re-run k8providerbuild.sh"
fi

# Show all PVCs in devpod namespace
DEVPOD_PVCS=$(kubectl get pvc -n devpod --no-headers 2>/dev/null)
if [ -n "$DEVPOD_PVCS" ]; then
    echo ""
    echo "   Current PVCs in devpod namespace:"
    kubectl get pvc -n devpod 2>/dev/null | while IFS= read -r line; do
        echo "   │  $line"
    done
fi

echo ""
echo "--------------------------------------------------------"
echo "📊 STEP 5: Resource Stress Check..."
kubectl describe nodes | grep -A 5 "Allocated resources"
echo "⚠️  If CPU limits are >150%, builds may time out at 99%."

echo ""
echo "--------------------------------------------------------"
echo "💽 STEP 5b: Ephemeral Storage Check..."
echo "(This is the #1 cause of ContainerStatusUnknown evictions)"
echo ""
# Check each node's ephemeral storage allocation
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    echo "  Node: $node"
    ALLOC=$(kubectl describe node "$node" | grep -A 3 "ephemeral-storage")
    if [ -n "$ALLOC" ]; then
        echo "$ALLOC" | sed 's/^/    /'
    else
        echo "    (no ephemeral-storage info — check node describe manually)"
    fi
    echo ""
done

echo "--------------------------------------------------------"
echo "👻 STEP 6: Ghost Pod Detection..."
GHOST_PODS=$(kubectl get pods -n devpod --no-headers 2>/dev/null | grep -E "ContainerStatusUnknown|Unknown|Evicted")
if [ -n "$GHOST_PODS" ]; then
    echo "⚠️  GHOST PODS DETECTED (evicted/unknown state):"
    echo "$GHOST_PODS"
    echo ""
    echo "💡 Fix: kubectl delete pod <name> -n devpod --force --grace-period=0"
    echo "   Or run k8providerbuild.sh to nuke and rebuild everything."
else
    echo "✅ No ghost pods. All devpod containers are healthy."
fi

echo ""
echo "--------------------------------------------------------"
echo "📦 STEP 7: Active Pods Overview..."
kubectl get pods -A -o wide

echo "--------------------------------------------------------"
echo "🚀 Pre-flight complete. RUN DEVPOD IN THIS SAME TERMINAL."
