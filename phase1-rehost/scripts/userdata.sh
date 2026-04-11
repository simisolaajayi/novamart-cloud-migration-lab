#!/bin/bash
# =============================================================================
# NovaMart EC2 User Data Script — Phase 1: Rehost (Lift and Shift)
# =============================================================================
# This script runs automatically when the EC2 instance first boots.
# It installs dependencies, clones the application, and starts the server.
#
# You can view the execution log at: /var/log/cloud-init-output.log
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Step 1: Update system packages
# -----------------------------------------------------------------------------
# Always start by updating the OS packages to get the latest security patches.
echo ">>> Updating system packages..."
dnf update -y

# -----------------------------------------------------------------------------
# Step 2: Install Node.js 18
# -----------------------------------------------------------------------------
# Amazon Linux 2023 supports Node.js via dnf. We install Node.js 18.x which
# is the LTS version our application requires.
echo ">>> Installing Node.js 18..."
dnf install -y nodejs18 npm

# Verify the installation
node --version
npm --version

# -----------------------------------------------------------------------------
# Step 3: Install Git
# -----------------------------------------------------------------------------
# We need git to clone the application repository from GitHub.
echo ">>> Installing git..."
dnf install -y git

# -----------------------------------------------------------------------------
# Step 4: Clone the application repository
# -----------------------------------------------------------------------------
# IMPORTANT: Replace this URL with your actual repository URL!
# If your repo is private, you will need to configure authentication.
echo ">>> Cloning application repository..."
REPO_URL="https://github.com/simisolaajayi/novamart-cloud-migration-lab.git"
APP_DIR="/opt/novamart"

git clone "$REPO_URL" "$APP_DIR" || {
  echo "WARNING: Could not clone repo. Creating placeholder directory."
  echo "You will need to manually clone or copy the application code."
  mkdir -p "$APP_DIR/on-premises/app"
}

# -----------------------------------------------------------------------------
# Step 5: Install application dependencies
# -----------------------------------------------------------------------------
# Navigate into the on-premises app directory and install Node.js packages.
echo ">>> Installing application dependencies..."
cd "$APP_DIR/on-premises/app"
npm install

# -----------------------------------------------------------------------------
# Step 6: Set environment variables
# -----------------------------------------------------------------------------
# We set ENVIRONMENT=aws-ec2 so the application knows it is running on AWS.
# The app can use this to display the current environment in its UI or logs.
echo ">>> Setting environment variables..."
export ENVIRONMENT=aws-ec2

# -----------------------------------------------------------------------------
# Step 7: Create a systemd service for the application
# -----------------------------------------------------------------------------
# Using systemd ensures the app starts automatically on reboot and can be
# managed with standard Linux service commands (systemctl start/stop/status).
echo ">>> Creating systemd service..."
cat > /etc/systemd/system/novamart.service <<'SERVICE'
[Unit]
Description=NovaMart Inventory Management Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/novamart/on-premises/app
Environment=NODE_ENV=production
Environment=ENVIRONMENT=aws-ec2
Environment=PORT=3000
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# -----------------------------------------------------------------------------
# Step 8: Start the application
# -----------------------------------------------------------------------------
echo ">>> Starting NovaMart application..."
systemctl daemon-reload
systemctl enable novamart
systemctl start novamart

echo ">>> NovaMart deployment complete!"
echo ">>> The application should be available on port 3000."
echo ">>> Check status with: systemctl status novamart"
echo ">>> View logs with: journalctl -u novamart -f"
