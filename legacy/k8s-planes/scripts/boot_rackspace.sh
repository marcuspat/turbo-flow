#!/bin/bash

# --- Initial Cleanup ---
echo "🧹 Cleaning up existing devpods directory..."
rm -rf devpods

# --- Original "postCreateCommand" ---
echo "⚙️ Running postCreateCommand tasks..."
# 1. Update and install packages
sudo apt-get update && sudo apt-get install -y tmux htop

# 2. Clone the repo and move the devpods content
# Execution is from workspace root, so 'cd ${containerWorkspaceFolder}' is effectively 'cd .'
git clone https://github.com/marcuspat/turbo-flow-claude
# Copy the devpods directory from the clone into the current directory (workspace root)
cp -r turbo-flow-claude/devpods .
# Remove the temporary clone
rm -rf turbo-flow-claude

# 3. Set permissions and run setup script
# Run chmod on scripts inside the newly copied devpods directory
chmod +x devpods/*.sh 2>/dev/null || true

# Run setup.sh if it exists (using relative path from workspace root)
if [ -f devpods/setup.sh ]; then
  ./devpods/setup.sh
fi
echo "✅ postCreateCommand finished."

---

# --- Original "postStartCommand" ---
echo "⏳ Running postStartCommand tasks..."
echo '✅ Container started, waiting for VS Code...'
echo "✅ postStartCommand finished."

---

# --- Original "postAttachCommand" ---
echo "🔌 Running postAttachCommand tasks..."
# Run post-setup.sh if it exists
if [ -f devpods/post-setup.sh ]; then
  chmod +x devpods/post-setup.sh
  ./devpods/post-setup.sh
fi

# Run tmux-workspace.sh logic if it exists
if [ -f devpods/tmux-workspace.sh ]; then
  chmod +x devpods/tmux-workspace.sh
  # The original command modifies the script to 'echo "✅ tmux workspace ready"' instead of attaching.
  sed 's/tmux attach-session -t workspace/echo \"✅ tmux workspace ready\"/' devpods/tmux-workspace.sh | bash
fi
echo "✅ postAttachCommand finished."

echo "🎉 All setup commands executed."
