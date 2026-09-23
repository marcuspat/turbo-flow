# Complete Guide: Setting Up DevPod with Rackspace Spot

This guide will walk you through setting up DevPod to run cloud-based development containers on Rackspace Spot's Kubernetes infrastructure at ~$0.04/hour (approximately $28.80/month for 24/7 usage).

## What You're Getting

- **Cloud-based dev containers** similar to GitHub Codespaces
- **Cost**: ~$0.04/hour vs Codespaces' $0.18-0.36/hour
- **Full Linux environments** with persistent storage
- **Access from anywhere** - your code lives in the cloud
- **Auto-stop after inactivity** to save money

## Prerequisites

1. **Install DevPod**: Download from [devpod.sh](https://devpod.sh)
2. **Rackspace Spot Account**: Sign up at [spot.rackspace.com](https://spot.rackspace.com)
3. **kubectl**: Install on your local machine
4. **Create a Kubernetes cluster** in Rackspace Spot dashboard

## Step 1: Get Your Kubeconfig

1. Log into your Rackspace Spot dashboard
2. Navigate to your Kubernetes cluster
3. Download the kubeconfig file
4. Save it to `~/.kube/devpod-kubeconfig.yaml`

```bash
# Create the .kube directory if it doesn't exist
mkdir -p ~/.kube

# Copy your downloaded kubeconfig
cp /path/to/downloaded/kubeconfig.yaml ~/.kube/devpod-kubeconfig.yaml

# Test the connection
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get nodes
```

## Step 2: Check Your Node Resources

Find out what resources you're paying for:

```bash
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get node -o json | grep -A 10 "allocatable"
```

Look for the CPU and memory values. A typical $0.04/hour node has approximately:
- **CPU**: 3.5 cores
- **Memory**: ~13.5Gi

## Step 3: Configure DevPod Provider

Add and configure the Kubernetes provider:

```bash
# Add the Kubernetes provider
devpod provider add kubernetes --name rackspace-spot

# Configure with your settings (adjust resources based on Step 2)
devpod provider set-options rackspace-spot \
  -o KUBERNETES_CONFIG=$HOME/.kube/devpod-kubeconfig.yaml \
  -o KUBERNETES_CONTEXT=jmp_agentics-devpods \
  -o KUBERNETES_NAMESPACE=devpod \
  -o DISK_SIZE=20Gi \
  -o CREATE_NAMESPACE=true \
  -o INACTIVITY_TIMEOUT=5h \
  -o RESOURCES="requests.cpu=2,requests.memory=8Gi,limits.cpu=3,limits.memory=12Gi"

# Set as default provider
devpod provider use rackspace-spot

# Verify settings
devpod provider options rackspace-spot
```

### Configuration Explained

- **KUBERNETES_CONFIG**: Path to your kubeconfig file
- **KUBERNETES_CONTEXT**: Context name from your kubeconfig (check with `kubectl config get-contexts`)
- **KUBERNETES_NAMESPACE**: Namespace for DevPod workspaces (creates if doesn't exist)
- **DISK_SIZE**: Persistent storage per workspace
- **INACTIVITY_TIMEOUT**: Auto-stop after inactivity (5h = 5 hours)
- **RESOURCES**: CPU/memory allocation per workspace
  - `requests`: Guaranteed minimum resources
  - `limits`: Maximum resources the workspace can use

## Step 4: Add DevContainer Configuration to Your Repository

**IMPORTANT**: Before creating your first workspace, you need to add the devcontainer configuration to your repository.

### Option 1: Add Directly to Your Repo (Recommended)

```bash
# Clone your repository
git clone https://github.com/yourusername/your-repo
cd your-repo

# Create the .devcontainer directory
mkdir -p .devcontainer

# Download the devcontainer configuration
curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

# Commit and push
git add .devcontainer/devcontainer.json
git commit -m "Add DevPod devcontainer configuration"
git push
```

### Option 2: Manual Creation

Create `.devcontainer/devcontainer.json` in your repository with this content:

```json
{
    "name": "Claude Dev Workspace",
    "image": "mcr.microsoft.com/devcontainers/base:debian",
    "remoteUser": "vscode",
    "features": {
        "ghcr.io/devcontainers/features/rust:1": {
            "version": "1.70"
        },
        "ghcr.io/devcontainers/features/docker-in-docker:2": {
            "moby": false
        },
        "ghcr.io/devcontainers/features/node:1": {}
    },
    "containerEnv": {
        "WORKSPACE_FOLDER": "${containerWorkspaceFolder}",
        "DEVPOD_WORKSPACE_FOLDER": "${containerWorkspaceFolder}",
        "AGENTS_DIR": "${containerWorkspaceFolder}/agents"
    },
    "postCreateCommand": "sudo apt-get update && sudo apt-get install -y tmux htop && cd ${containerWorkspaceFolder} && git clone https://github.com/marcuspat/turbo-flow-claude && cp -r turbo-flow-claude/devpods . && rm -rf turbo-flow-claude && chmod +x ${containerWorkspaceFolder}/devpods/*.sh 2>/dev/null || true && if [ -f ${containerWorkspaceFolder}/devpods/setup.sh ]; then ${containerWorkspaceFolder}/devpods/setup.sh; fi",
    "postStartCommand": "echo '✅ Container started, waiting for VS Code...'",
    "postAttachCommand": "if [ -f ${containerWorkspaceFolder}/devpods/post-setup.sh ]; then chmod +x ${containerWorkspaceFolder}/devpods/post-setup.sh && ${containerWorkspaceFolder}/devpods/post-setup.sh; fi && if [ -f ${containerWorkspaceFolder}/devpods/tmux-workspace.sh ]; then chmod +x ${containerWorkspaceFolder}/devpods/tmux-workspace.sh && sed 's/tmux attach-session -t workspace/echo \"✅ tmux workspace ready\"/' ${containerWorkspaceFolder}/devpods/tmux-workspace.sh | bash; fi",
    "customizations": {
        "vscode": {
            "extensions": [
                "rooveterinaryinc.roo-cline",
                "vsls-contrib.gistfs",
                "github.copilot",
                "github.copilot-chat"
            ],
            "settings": {
                "terminal.integrated.cwd": "${containerWorkspaceFolder}",
                "terminal.integrated.shellIntegration.enabled": true,
                "workbench.startupEditor": "none",
                "terminal.integrated.profiles.linux": {
                    "tmux-workspace": {
                        "path": "/bin/bash",
                        "args": ["-c", "tmux attach-session -t workspace 2>/dev/null || bash"]
                    }
                },
                "terminal.integrated.defaultProfile.linux": "tmux-workspace"
            }
        }
    }
}
```

### What This DevContainer Does

- **Base Image**: Debian-based development container
- **Features**: Installs Rust, Docker-in-Docker, and Node.js
- **Setup Scripts**: Automatically clones turbo-flow-claude repo and copies custom setup scripts
- **VS Code Extensions**: Installs Roo Cline, GitHub Copilot, and other productivity tools
- **tmux Integration**: Sets up tmux workspace for persistent terminal sessions

## Step 5: Create Your First Workspace

**After adding the devcontainer.json to your repository**, create your workspace:

```bash
# From a GitHub repository
devpod up https://github.com/yourusername/your-repo
```

### What Happens During First Launch

1. DevPod clones your repository to the Kubernetes pod
2. Reads `.devcontainer/devcontainer.json`
3. Pulls the base Debian image
4. Installs Rust, Docker-in-Docker, and Node.js features
5. Runs `postCreateCommand`:
   - Installs tmux and htop
   - Clones turbo-flow-claude for setup scripts
   - Copies `devpods/` folder to your workspace
   - Runs `setup.sh` if it exists
6. Opens VS Code connected to the remote container

## Step 6: Quick Start Script (Optional)

Create a script to quickly add the devcontainer to new repositories:

```bash
#!/bin/bash
# Save as ~/bin/add-devcontainer.sh

REPO_PATH=$1

if [ -z "$REPO_PATH" ]; then
  echo "Usage: add-devcontainer.sh /path/to/repo"
  exit 1
fi

cd "$REPO_PATH" || exit 1
mkdir -p .devcontainer

curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

echo "✅ DevContainer configuration added!"
echo "Next steps:"
echo "  git add .devcontainer/devcontainer.json"
echo "  git commit -m 'Add DevPod configuration'"
echo "  git push"
echo "  devpod up https://github.com/yourusername/$(basename "$REPO_PATH")"
```

Make it executable:

```bash
chmod +x ~/bin/add-devcontainer.sh
```

Use it:

```bash
add-devcontainer.sh ~/Projects/my-repo
```

## Managing Workspaces

### View All Workspaces
```bash
devpod list
```

### Stop a Workspace (Preserves Data)
```bash
devpod stop workspace-name
```

### Restart a Workspace
```bash
devpod up workspace-name
```

### Delete a Workspace (Removes Everything)
```bash
devpod delete workspace-name
```

### SSH into a Workspace
```bash
devpod ssh workspace-name
```

## Important Considerations

### Resource Limits
With a 3.5 CPU / 13.5Gi RAM node:
- You can run **~1 workspace at full capacity**
- Or **2-3 smaller workspaces** if you reduce resource limits
- Stopped workspaces don't consume resources

### Multiple Workspaces
```bash
# Each repo gets its own pod
devpod up https://github.com/user/project1
devpod up https://github.com/user/project2
devpod up https://github.com/user/project3

# Only active workspaces use resources
```

### Cost Management

**Set a Budget Alert:**
1. Log into [Rackspace Customer Portal](https://manage.rackspace.com)
2. Go to **Billing** → **Set Billing Threshold**
3. Set your monthly limit (e.g., $40-50)
4. You'll receive email alerts when approaching the limit

**Cost Breakdown:**
- 1 node 24/7: ~$28.80/month
- Storage (20Gi PVC): ~$2-3/month
- Network egress: Minimal for dev work
- **Total**: ~$30-35/month

**Cost Optimization:**
- Use the 5-hour inactivity timeout (workspaces auto-stop)
- Stop workspaces when switching projects
- Delete workspaces you no longer need

## Troubleshooting

### Insufficient Resources Error
```
0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory
```

**Solution**: Stop other workspaces or reduce resource requests:

```bash
# Stop unused workspace
devpod stop other-workspace

# Or lower resource limits
devpod provider set-options rackspace-spot \
  -o RESOURCES="requests.cpu=1,requests.memory=4Gi,limits.cpu=3,limits.memory=12Gi"
```

### Token Expiration
Your kubeconfig token will expire periodically. When it does:
1. Download a fresh kubeconfig from Rackspace Spot dashboard
2. Replace `~/.kube/devpod-kubeconfig.yaml`
3. Existing workspaces will reconnect automatically

### Check Pod Status
```bash
# View all pods
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get pods -n devpod

# Get pod logs
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml logs -n devpod POD_NAME --tail=50
```

### Workspace Won't Start
```bash
# Delete and recreate with debug output
devpod delete workspace-name --force
devpod up https://github.com/user/repo --debug
```

### DevContainer Not Found
If you get an error about missing devcontainer.json:
```bash
# Make sure you committed it to your repo
git add .devcontainer/devcontainer.json
git commit -m "Add devcontainer config"
git push

# Then delete and recreate the workspace
devpod delete workspace-name --force
devpod up https://github.com/user/repo
```

## Quick Reference

```bash
# Add devcontainer to repo
mkdir -p .devcontainer
curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

# Create workspace
devpod up https://github.com/user/repo

# List workspaces
devpod list

# Stop workspace (save state)
devpod stop workspace-name

# Start workspace
devpod up workspace-name

# Delete workspace (permanent)
devpod delete workspace-name

# SSH into workspace
devpod ssh workspace-name

# View logs
devpod logs workspace-name

# Check provider options
devpod provider options rackspace-spot
```

## Benefits Over Traditional Development

✅ **Cost-effective**: ~$30/month vs $100-300 for AWS/GCP  
✅ **Work from anywhere**: Access from any device with VS Code  
✅ **Consistent environments**: Same setup across all projects  
✅ **Resource flexibility**: Scale CPU/RAM as needed  
✅ **Auto-cleanup**: Workspaces stop when inactive  
✅ **No local dependencies**: Keep your laptop fast and clean  
✅ **Custom tooling**: Automatic setup scripts via turbo-flow-claude  
✅ **tmux integration**: Persistent terminal sessions  

---

**Need Help?**
- DevPod Docs: [devpod.sh/docs](https://devpod.sh/docs)
- Rackspace Spot Docs: [spot.rackspace.com/docs](https://spot.rackspace.com/docs)
- Rackspace Support: [support.rackspace.com](https://support.rackspace.com)
- Reference DevContainer: [turbo-flow-claude/devpods](https://github.com/marcuspat/turbo-flow-claude/tree/main/devpods)
