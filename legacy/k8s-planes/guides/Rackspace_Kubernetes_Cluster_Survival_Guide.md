# Rackspace Kubernetes Cluster Survival Guide
## Dealing with Recurring Issues Without Losing Your Mind

This guide is for when your Rackspace cluster acts up (again). Skip the theory, here are the fixes that actually work.

---

## Table of Contents
1. [Quick Reference Commands](#-quick-reference-commands)
2. [Quick Fixes: The Greatest Hits](#quick-fixes-the-greatest-hits)
3. [The "Oh Sh*t" Checklist](#the-oh-shit-checklist)
4. [Common Recurring Issues](#common-recurring-issues)
5. [Automated Health Checks](#automated-health-checks)
6. [Nuclear Options](#nuclear-options)
7. [Prevention & Monitoring](#prevention--monitoring)

---

## Quick Reference Commands

Copy & paste these when sh*t hits the fan. No explanations, just fixes.

### Connection Issues

```bash
# Fix expired token / can't connect
unset KUBECONFIG
cp fresh-kubeconfig.yaml ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes

# Switch to OIDC (auto-refreshing tokens)
kubectl config use-context jmp_agentics-devpods-1-oidc
```

### Pod Issues

```bash
# Force delete stuck pod
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# Delete all non-running pods in a namespace
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Find all problematic pods
kubectl get pods -A | grep -v "Running\|Completed"

# Get pod details and events
kubectl describe pod <pod-name> -n <namespace>

# Get pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Shell into pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
```

### Cluster Health Checks

```bash
# Quick health overview
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -10

# Check all components
kubectl get pods -n kube-system
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver

# Check storage
kubectl get pvc -A
```

### Node Issues

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Cordon and drain problem node
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# Uncordon after fix
kubectl uncordon <node-name>
```

### Networking Issues

```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Restart Calico
kubectl delete pods -n calico-system --all
kubectl delete pods -n calico-apiserver --all

# Test DNS from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Network debug pod
kubectl run -it --rm netdebug --image=nicolaka/netshoot --restart=Never -- bash
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -A

# Describe PVC for issues
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage classes
kubectl get storageclass

# Force unmount (delete old pod first)
kubectl delete pod <old-pod-name> -n <namespace> --force --grace-period=0
```

### Mass Operations

```bash
# Delete all pods in Unknown/Error state (CAREFUL!)
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns pod; do kubectl delete pod $pod -n $ns --force --grace-period=0; done

# Restart all deployments in a namespace
kubectl rollout restart deployment -n <namespace>

# Scale down all deployments in namespace
kubectl get deployments -n <namespace> -o name | xargs -I {} kubectl scale {} --replicas=0 -n <namespace>

# Scale back up
kubectl get deployments -n <namespace> -o name | xargs -I {} kubectl scale {} --replicas=1 -n <namespace>
```

### Information Gathering

```bash
# Get all pod info with node placement
kubectl get pods -A -o wide

# Find pods with high restarts
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | "\(.metadata.namespace)/\(.metadata.name) restarts: \(.status.containerStatuses[].restartCount)"'

# Get all resources in namespace
kubectl get all -n <namespace>

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Get cluster info
kubectl cluster-info
kubectl version
```

### Useful Aliases (Add to ~/.zshrc)

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kdel='kubectl delete'
alias khealth='kubectl get nodes && echo "" && kubectl get pods -A | grep -v Running | grep -v Completed'
alias kn='kubectl config set-context --current --namespace'
```

### Emergency "Everything is Broken" Command

```bash
# Run all health checks at once
echo "=== NODES ===" && kubectl get nodes && \
echo -e "\n=== PROBLEM PODS ===" && kubectl get pods -A | grep -v "Running\|Completed" && \
echo -e "\n=== RECENT EVENTS ===" && kubectl get events -A --sort-by='.lastTimestamp' | tail -15 && \
echo -e "\n=== RESOURCE USAGE ===" && kubectl top nodes && \
echo -e "\n=== COREDNS ===" && kubectl get pods -n kube-system -l k8s-app=kube-dns && \
echo -e "\n=== CALICO ===" && kubectl get pods -n calico-system
```

---

## Quick Fixes: The Greatest Hits

### Issue: Pods Stuck in `ContainerStatusUnknown`

**What it means:** The node lost connection to the pod. Kubernetes doesn't know if the pod is alive or dead.

**Quick Fix:**
```bash
# Force delete the stuck pod
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# If it's part of a deployment/statefulset, it will auto-recreate
# Check if it recreates
kubectl get pods -n <namespace> -w
```

**Why this works:** Kubernetes clears the stuck state and starts fresh. If it's managed by a controller, it'll recreate automatically.

**Prevention:**
```bash
# Add this to your pod spec to handle node issues better
spec:
  terminationGracePeriodSeconds: 30
  tolerations:
  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 30
  - key: "node.kubernetes.io/not-ready"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 30
```

---

### Issue: Can't Connect to Cluster (DNS Lookup Failures)

**Symptoms:**
```
dial tcp: lookup hcp-XXXXX.spot.rackspace.com: no such host
```

**Quick Fix:**
```bash
# 1. Check if you have the right kubeconfig
kubectl config view --minify

# 2. Download fresh kubeconfig from Rackspace control panel
# Place it in your current directory as 'new-kubeconfig.yaml'

# 3. Replace your config
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d)
cp new-kubeconfig.yaml ~/.kube/config
chmod 600 ~/.kube/config

# 4. Check for environment variables interfering
echo $KUBECONFIG
# If it's set to something, unset it or fix it
unset KUBECONFIG

# 5. Test
kubectl get nodes
```

**Root Cause:** Either your auth token expired (they expire after ~3 days), or the cluster was rebuilt with a new endpoint UUID.

---

### Issue: Expired Authentication Token

**Symptoms:**
```
Unable to connect to the server: Unauthorized
```

**Quick Fix:**
```bash
# Download fresh kubeconfig from Rackspace (auth tokens expire)
# Replace your local config
cp fresh-kubeconfig.yaml ~/.kube/config

# Or if you have OIDC configured, refresh the token
kubectl oidc-login get-token
```

**Prevention:** Set up OIDC authentication instead of static tokens - they auto-refresh.

---

### Issue: Nodes Showing as `NotReady`

**Check it:**
```bash
kubectl get nodes
```

**Quick Fix:**
```bash
# Describe the problematic node
kubectl describe node <node-name>

# Common fixes:

# 1. Node out of resources - check usage
kubectl top node <node-name>

# 2. Networking issue - restart the node from Rackspace panel
# Go to: Rackspace Control Panel → Cluster → Nodes → Restart

# 3. If node is truly dead, cordon and drain it
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Then delete from Rackspace panel and let it auto-scale a new one
```

---

### Issue: Pods Stuck in `Pending` Forever

**Quick Diagnostic:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 Events
```

**Common Causes & Fixes:**

**1. Insufficient Resources:**
```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Fix: Scale up node pool in Rackspace panel
```

**2. PVC Not Binding:**
```bash
# Check PVC status
kubectl get pvc -n <namespace>

# If stuck, check storage class
kubectl get storageclass
kubectl describe pvc <pvc-name> -n <namespace>

# Fix: Delete and recreate PVC, or provision storage in Rackspace panel
```

**3. Image Pull Issues:**
```bash
# Check events
kubectl describe pod <pod-name> -n <namespace>

# Common fixes:
# - Add image pull secrets
# - Check if image exists
# - Verify registry authentication
```

---

## The "Oh Sh*t" Checklist

When everything is on fire, run these commands in order:

### 1. Check Cluster Connectivity
```bash
# Can you reach the cluster at all?
kubectl cluster-info

# If no:
# - Download fresh kubeconfig from Rackspace
# - Check Rackspace status page: https://status.rackspace.com
# - Unset any KUBECONFIG environment variables
```

### 2. Check Node Health
```bash
# Are all nodes ready?
kubectl get nodes

# Any nodes NotReady or Unknown?
# → Go to Rackspace panel and restart those nodes
```

### 3. Check Pod Status Across Cluster
```bash
# What's actually running?
kubectl get pods -A

# Focus on:
# - Anything in CrashLoopBackOff
# - Anything in Error
# - Anything in Pending for >5 minutes
# - Anything in Unknown/ContainerStatusUnknown
```

### 4. Check Recent Events
```bash
# What just happened?
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Look for:
# - FailedScheduling
# - FailedMount
# - ImagePullBackOff
# - OOMKilled
# - Evicted
```

### 5. Check Resource Pressure
```bash
# Are nodes under resource pressure?
kubectl top nodes
kubectl top pods -A --sort-by=memory

# If nodes are at >80% memory or CPU:
# → Scale up in Rackspace panel immediately
```

### 6. Check Storage Issues
```bash
# Any PVC issues?
kubectl get pvc -A

# Any stuck in Pending?
# → Check Rackspace Cloud Block Storage status
```

---

## Common Recurring Issues

### The "Token Expired Again" Problem

Rackspace Spot tokens expire quickly (~3 days). Stop manually downloading configs.

**Permanent Fix - Use OIDC:**

Your kubeconfig already has OIDC configured! Switch to it:
```bash
# List your contexts
kubectl config get-contexts

# Switch to the OIDC context (looks like: jmp_agentics-devpods-1-oidc)
kubectl config use-context jmp_agentics-devpods-1-oidc

# Install kubectl oidc-login plugin if needed
brew install int128/kubelogin/kubelogin

# Test
kubectl get nodes
# This will auto-refresh tokens!
```

---

### The "Random Pod Death" Problem

**Symptoms:** Pods randomly die or go into Unknown status.

**Root Causes:**
1. Node pressure (OOM, disk pressure)
2. Rackspace infrastructure hiccups
3. Pod evictions due to resource constraints

**Fix:**
```bash
# 1. Set proper resource limits on ALL pods
kubectl set resources deployment <deployment-name> \
  --limits=cpu=2,memory=4Gi \
  --requests=cpu=1,memory=2Gi \
  -n <namespace>

# 2. Add pod disruption budgets
kubectl create pdb <pdb-name> \
  --selector=app=<your-app> \
  --min-available=1 \
  -n <namespace>

# 3. Enable pod anti-affinity to spread across nodes
# Add to your deployment:
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - <your-app>
              topologyKey: kubernetes.io/hostname
```

---

### The "Networking is Broken" Problem

**Symptoms:**
- Pods can't reach services
- DNS not resolving
- External traffic not reaching cluster

**Quick Diagnostic:**
```bash
# Test DNS from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Test service connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# Then inside: curl http://<service-name>.<namespace>.svc.cluster.local

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Common Fixes:**

**1. Restart CoreDNS:**
```bash
kubectl rollout restart deployment coredns -n kube-system
```

**2. Check Calico (Rackspace uses Calico):**
```bash
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver

# If any are failing, restart them
kubectl delete pod <pod-name> -n calico-system
```

**3. Check NetworkPolicies:**
```bash
# List all network policies
kubectl get networkpolicies -A

# If you suspect they're blocking traffic, describe them
kubectl describe networkpolicy <policy-name> -n <namespace>

# Nuclear option: delete problematic policies
kubectl delete networkpolicy <policy-name> -n <namespace>
```

---

### The "Storage Won't Mount" Problem

**Symptoms:**
- Pods stuck in ContainerCreating
- Events show FailedMount errors

**Quick Fix:**
```bash
# Check the pod events
kubectl describe pod <pod-name> -n <namespace> | grep -A 20 Events

# Common issues:

# 1. Volume already attached to another node
# → Force delete the old pod first
kubectl delete pod <old-pod-name> -n <namespace> --force --grace-period=0

# 2. PVC doesn't exist or isn't bound
kubectl get pvc -n <namespace>
# → Check Rackspace Cloud Block Storage, ensure volume exists

# 3. Storage class missing
kubectl get storageclass
# → Use 'rackspace-standard' or 'rackspace-ssd'

# 4. Volume still attached in Rackspace
# → Go to Rackspace panel → Cloud Block Storage → Detach the volume
```

---

## Automated Health Checks

### Create a Daily Health Check Script

Save this as `check-cluster-health.sh`:

```bash
#!/bin/bash

echo "=== Cluster Health Check ==="
echo "Date: $(date)"
echo ""

echo "=== Node Status ==="
kubectl get nodes
echo ""

echo "=== Problematic Pods ==="
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAMESPACE"
echo ""

echo "=== Recent Events (Last 15) ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -15
echo ""

echo "=== Resource Usage ==="
kubectl top nodes
echo ""

echo "=== Pods Using Most Memory ==="
kubectl top pods -A --sort-by=memory | head -10
echo ""

echo "=== PVC Status ==="
kubectl get pvc -A | grep -v "Bound"
echo ""

echo "=== Pods in Unknown/ContainerStatusUnknown ==="
kubectl get pods -A | grep -E "Unknown|ContainerStatusUnknown"
echo ""

echo "=== CoreDNS Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""

echo "=== Calico Status ==="
kubectl get pods -n calico-system
echo ""

# Check for pods that need force deletion
echo "=== Pods That Should Be Force Deleted ==="
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.phase == "Unknown" or (.status.containerStatuses[]?.state.waiting.reason == "ContainerStatusUnknown")) | "\(.metadata.namespace) \(.metadata.name)"'

echo ""
echo "=== Health Check Complete ==="
```

Make it executable:
```bash
chmod +x check-cluster-health.sh
```

Run it daily:
```bash
# Add to crontab (runs at 9 AM daily)
crontab -e
# Add this line:
0 9 * * * /path/to/check-cluster-health.sh > /path/to/cluster-health-$(date +\%Y\%m\%d).log
```

---

### Auto-Cleanup Script for Stuck Pods

Save this as `cleanup-stuck-pods.sh`:

```bash
#!/bin/bash

echo "=== Cleaning Up Stuck Pods ==="

# Force delete pods in Unknown or ContainerStatusUnknown state
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.phase == "Unknown" or (.status.containerStatuses[]?.state.waiting.reason == "ContainerStatusUnknown")) | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    echo "Force deleting: $pod in namespace $namespace"
    kubectl delete pod $pod -n $namespace --force --grace-period=0
  done

# Restart any pods that have been restarting too much
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 10) | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    echo "High restart count detected for: $pod in namespace $namespace"
    echo "  Consider investigating or scaling down/up the deployment"
  done

echo "=== Cleanup Complete ==="
```

Make it executable:
```bash
chmod +x cleanup-stuck-pods.sh
```

**CAUTION:** Only run this if you understand what it does. It force-deletes pods.

---

## Nuclear Options

When nothing else works and you need to get things running NOW.

### Nuclear Option 1: Restart All Problematic Pods

```bash
# Delete all pods not in Running or Completed state
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    kubectl delete pod $pod -n $namespace --force --grace-period=0
  done
```

### Nuclear Option 2: Restart All CoreDNS and Networking

```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Restart Calico components
kubectl delete pods -n calico-system --all
kubectl delete pods -n calico-apiserver --all

# Wait for them to come back
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s
```

### Nuclear Option 3: Drain and Restart Problem Nodes

```bash
# Identify the problematic node
kubectl get nodes

# Cordon it (prevent new pods from scheduling)
kubectl cordon <node-name>

# Drain it (move existing pods off)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# Go to Rackspace panel and restart the node
# Or delete the node and let auto-scaling create a new one

# After node is back, uncordon
kubectl uncordon <node-name>
```

### Nuclear Option 4: Full Cluster Restart (Last Resort)

```bash
# This is DESTRUCTIVE - backup everything first!

# 1. Scale down all deployments
kubectl get deployments -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace deployment; do
    kubectl scale deployment $deployment -n $namespace --replicas=0
  done

# 2. Wait a minute, then scale back up
sleep 60

kubectl get deployments -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace deployment; do
    kubectl scale deployment $deployment -n $namespace --replicas=1
  done
```

---

## Prevention & Monitoring

### 1. Set Up Proper Resource Limits

Never deploy without resource limits:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### 2. Use Horizontal Pod Autoscaling

```bash
# Auto-scale based on CPU
kubectl autoscale deployment <deployment-name> \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n <namespace>
```

### 3. Set Up Pod Disruption Budgets

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

### 4. Enable Monitoring

Use Rackspace Intelligence or set up Prometheus:

```bash
# Quick Prometheus setup (if not already installed)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 5. Create Alerts

Set up alerts for:
- Node NotReady
- Pods in CrashLoopBackOff for >5 minutes
- High memory/CPU usage (>80%)
- PVC mount failures
- CoreDNS failures

---

## Daily Workflow Recommendations

### Morning Routine (5 minutes):

```bash
# Run your health check
./check-cluster-health.sh

# Check for stuck pods
kubectl get pods -A | grep -E "Unknown|Error|CrashLoop|ImagePull"

# Clean up if needed
./cleanup-stuck-pods.sh
```

### Weekly Maintenance (30 minutes):

```bash
# Check for resource usage trends
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Check storage usage
kubectl get pvc -A

# Review and clean up old/unused resources
kubectl get all -A | grep -i <old-project-name>

# Update any pending workloads
kubectl get pods -A -o wide | grep -v "Running"
```

### Monthly Tasks:

1. Review and update resource limits based on actual usage
2. Check for Kubernetes version updates from Rackspace
3. Review Rackspace billing for over-provisioned resources
4. Update your kubeconfig (download fresh one)
5. Test disaster recovery procedures

---

## Quick Command Reference

### One-Liners for Common Tasks

```bash
# Force delete all pods in a namespace
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Get all pods not in Running state
kubectl get pods -A --field-selector=status.phase!=Running

# Get all events from last 15 minutes
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Find pods using the most memory
kubectl top pods -A --sort-by=memory | head -20

# Find pods with high restart counts
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | "\(.metadata.namespace)/\(.metadata.name) restarts: \(.status.containerStatuses[].restartCount)"'

# Check which node a pod is on
kubectl get pod <pod-name> -n <namespace> -o wide

# Get pod logs from all containers
kubectl logs <pod-name> -n <namespace> --all-containers=true

# Describe all nodes and check for issues
kubectl describe nodes | grep -A 5 "Conditions:"

# List all containers in a pod
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# Check PVC usage
kubectl get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage

# Get all resources in a namespace
kubectl api-resources --verbs=list -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>
```

---

## Environment Setup for Sanity

Add these to your `~/.zshrc` or `~/.bashrc`:

```bash
# Kubectl aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kdel='kubectl delete'

# Quick cluster health check
alias khealth='kubectl get nodes && echo "" && kubectl get pods -A | grep -v Running | grep -v Completed'

# Quick cleanup
alias kclean='kubectl delete pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --force --grace-period=0'

# Use the OIDC context by default (auto-refreshing tokens)
export KUBECONFIG=~/.kube/config
kubectl config use-context jmp_agentics-devpods-1-oidc 2>/dev/null

# Quick namespace switcher
alias kn='kubectl config set-context --current --namespace'
```

---

## Final Tips

1. **Always use OIDC authentication** - stops the expired token pain
2. **Set resource limits on everything** - prevents resource exhaustion
3. **Monitor daily** - catch issues before they cascade
4. **Document your incidents** - builds your knowledge base
5. **Automate cleanup** - don't manually delete stuck pods daily
6. **Use the health check script** - catches issues early
7. **Keep a fresh kubeconfig handy** - download it weekly
8. **Use labels and annotations** - makes debugging easier
9. **Test in dev first** - always

---

