#!/bin/bash
# ============================================================
# NovaMart Phase 2 — EC2 User Data Script
# Re-platform: App server connecting to RDS PostgreSQL
# ============================================================
set -euo pipefail

exec > /var/log/novamart-setup.log 2>&1
echo "=== NovaMart Phase 2 setup starting at $(date) ==="

# ----------------------------------------------------------
# 1. Install Node.js 18, Git, and PostgreSQL client tools
# ----------------------------------------------------------
echo ">>> Installing system packages..."
dnf update -y
dnf install -y git postgresql15

# Install Node.js 18 via NodeSource
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
dnf install -y nodejs

echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"
echo "psql version: $(psql --version)"

# ----------------------------------------------------------
# 2. Clone the application repository
# ----------------------------------------------------------
echo ">>> Cloning NovaMart application..."
cd /home/ec2-user
git clone https://github.com/anmutetech/cloud-migration-lab.git || {
  echo "Clone failed, retrying in 10 seconds..."
  sleep 10
  git clone https://github.com/anmutetech/cloud-migration-lab.git
}

# ----------------------------------------------------------
# 3. Install application dependencies (including pg driver)
# ----------------------------------------------------------
echo ">>> Installing Node.js dependencies..."
cd /home/ec2-user/cloud-migration-lab/on-premises/app
npm install
npm install pg   # PostgreSQL driver for Node.js

# ----------------------------------------------------------
# 4. Set environment variables for RDS PostgreSQL
#    These values are injected by Terraform templatefile()
# ----------------------------------------------------------
echo ">>> Configuring environment..."
cat > /home/ec2-user/cloud-migration-lab/on-premises/app/.env <<ENVFILE
ENVIRONMENT=aws-replatform
PORT=3000
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USERNAME=${db_username}
DB_PASSWORD=${db_password}
ENVFILE

# Also export for the current session (used by migration script)
export PGHOST="${db_host}"
export PGPORT="${db_port}"
export PGDATABASE="${db_name}"
export PGUSER="${db_username}"
export PGPASSWORD="${db_password}"

# ----------------------------------------------------------
# 5. Run database migration to create PostgreSQL schema
# ----------------------------------------------------------
echo ">>> Running database migration..."
chmod +x /home/ec2-user/cloud-migration-lab/phase2-replatform/scripts/migrate-database.sh
bash /home/ec2-user/cloud-migration-lab/phase2-replatform/scripts/migrate-database.sh || {
  echo "WARNING: Migration may have already been run by another instance."
}

# ----------------------------------------------------------
# 6. Set ownership and start the application
# ----------------------------------------------------------
echo ">>> Starting NovaMart application..."
chown -R ec2-user:ec2-user /home/ec2-user/cloud-migration-lab

# Create a systemd service for the app
cat > /etc/systemd/system/novamart.service <<SERVICE
[Unit]
Description=NovaMart Inventory Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/cloud-migration-lab/on-premises/app
EnvironmentFile=/home/ec2-user/cloud-migration-lab/on-premises/app/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable novamart
systemctl start novamart

echo "=== NovaMart Phase 2 setup complete at $(date) ==="
echo "Application should be available on port 3000"
