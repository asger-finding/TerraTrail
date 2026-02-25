#!/usr/bin/env bash
# TerraTrail VPS setup script
# SKAL KØRES SOM ROOT

set -euo pipefail

REPO="https://github.com/asger-finding/TerraTrail.git"
INSTALL_DIR="/opt/terratrail"
VPS_USER="terratrail"

echo "TerraTrail setup"

if id "$VPS_USER" &>/dev/null; then
    echo "Bruger '$VPS_USER' findes allerede, springer over."
else
    echo "Opretter systembruger '$VPS_USER' ..."
    useradd -r -s /usr/sbin/nologin "$VPS_USER"
fi

# Installer git-lfs
if command -v git-lfs &>/dev/null || git lfs version &>/dev/null 2>&1; then
    echo "Git LFS er allerede installeret"
else
    echo "Installerer git-lfs ..."
    apt-get install -y git-lfs || dnf install -y git-lfs || pacman -S --noconfirm git-lfs
fi
git lfs install

# Installer bun til /usr/local/bin
# så alle brugere kan køre det
if [ -x /usr/local/bin/bun ]; then
    echo "Bun er allerede installeret: $(/usr/local/bin/bun --version)"
else
    echo "Installerer bun til /usr/local/bin ..."
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash
    echo "Bun installeret: $(/usr/local/bin/bun --version)"
fi

# Klon dette repo eller pull (som service-brugeren)
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Repo findes allerede, puller seneste ændringer ..."
    sudo -u "$VPS_USER" git -C "$INSTALL_DIR" pull
else
    echo "Kloner repo til $INSTALL_DIR ..."
    mkdir -p "$INSTALL_DIR"
    chown "$VPS_USER:$VPS_USER" "$INSTALL_DIR"
    sudo -u "$VPS_USER" git clone "$REPO" "$INSTALL_DIR"
fi

# Disse mapper skal oprettes og ekistere
# for systemd ReadWritePaths
mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/backend/.keys"
chown -R "$VPS_USER:$VPS_USER" "$INSTALL_DIR"

echo "Installerer dependencies ..."
cd "$INSTALL_DIR/backend"
sudo -u "$VPS_USER" bun install --frozen-lockfile

if [ ! -f "$INSTALL_DIR/backend/.env" ]; then
    echo "Opretter standard .env ..."
    cat > "$INSTALL_DIR/backend/.env" <<'ENV'
PORT=3000
# MBTILES_PATH=/opt/terratrail/lfs/map.mbtiles
# JWT_KEYS_DIR=/opt/terratrail/backend/.keys
# JWT_EXPIRATION=24h
# USER_DB_PATH=/opt/terratrail/data/users.db
ENV
    chown "$VPS_USER:$VPS_USER" "$INSTALL_DIR/backend/.env"
fi

echo "Installerer systemd service ..."
cp "$INSTALL_DIR/backend/terratrail.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now terratrail

echo ""
echo "Setup færdigt"
echo "Status:"
systemctl status terratrail --no-pager
echo ""
echo "Logs tjekkes med: journalctl -u terratrail -f"
