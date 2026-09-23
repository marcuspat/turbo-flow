# 🚀 Setup for Google Cloud Shell 

## ⚡ Quick Setup Methods

### Setup for Google Cloud Shell  **

After the Google Cloud Shell  boots up, run this command:

```bash
touch boot.sh && chmod +x boot.sh && vi boot.sh
```
Then paste in the script below and run to finish setting up Turbo flow in Setup for Google Cloud Shell 

```bash
#!/bin/bash
# Clone the repository
echo "Cloning repository..."
git clone https://github.com/marcuspat/turbo-flow-claude.git

# Check if clone was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone repository"
    exit 1
fi

# Navigate into the cloned directory
cd turbo-flow-claude

# Move devpods directory to parent directory
echo "Moving devpods directory..."
mv devpods ..

# Go back to parent directory
cd ..

# Remove the cloned repository
echo "Removing turbo-flow-claude directory..."
rm -rf turbo-flow-claude

# Make all shell scripts in devpods executable
echo "Making scripts executable..."
chmod +x ./devpods/*.sh

# Run the setup script
echo "Running codespace_setup.sh..."
./devpods/codespace_setup.sh

echo "Script completed!"
```
---

## 📁 What Gets Installed

```
your-project/
├── devpods/                    # Setup scripts
├── agents/                     # AI agent library
├── cf-with-context.sh         # Context wrapper
├── CLAUDE.md                  # Claude development rules
├── FEEDCLAUDE.md              # Streamlined instructions
└── [project files]            # Your configured environment
```

---

## 🎯 Available Commands

```bash
cf "any task"              # General AI coordination
cf-swarm "build feature"   # Focused implementation
cf-hive "complex planning" # Multi-agent coordination
claude-monitor             # Usage tracking
```

---

## 🖥️ Tmux Workspace

Connect after setup:
```bash
tmux attach -t workspace
```

**Windows:**
- **0**: Primary Claude workspace
- **1**: Secondary Claude workspace  
- **2**: Claude monitor
- **3**: System monitor (htop)

**Navigation:**
- `Ctrl+b 0-3` - Switch windows
- `Ctrl+b d` - Detach session
- `Ctrl+b ?` - Help

---

## 💡 Quick Test

```bash
# After setup and connecting to tmux:
source ~/.bashrc
cf "Hello! Show me available agents"
```

---

## ⚠️ Troubleshooting

**Can't connect to tmux:**
```bash
tmux list-sessions
# If missing, run:
./devpods/tmux-workspace.sh
tmux attach -t workspace
```

**Commands not found:**
```bash
source ~/.bashrc
```

---

## 🎉 You're Ready!

Complete AI development environment  
✅ Extensive agent library  
✅ Monitoring tools  
✅ 4-window tmux workspace  

**Remember:** Always work inside tmux for the best experience!
