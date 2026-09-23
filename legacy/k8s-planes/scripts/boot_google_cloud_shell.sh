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
