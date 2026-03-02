#!/usr/bin/env bash
set -euo pipefail

cd /opt/terratrail

echo "Pulling latest changes ..."
git pull

echo "Installing dependencies ..."
cd backend
bun install --frozen-lockfile

echo "Restarting service ..."
sudo systemctl restart terratrail

echo "Deploy completed. Status:"
systemctl status terratrail --no-pager
