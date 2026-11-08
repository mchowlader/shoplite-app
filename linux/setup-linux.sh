#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Linux Administration & Security Automation
# Question 3: Users, Permissions (setfacl), SSH Hardening, Systemd, Firewall
# ==============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run with sudo or as root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "    ShopLite Question 3: Linux Hardening & Administration "
echo "=========================================================="

# ------------------------------------------------------------------------------
# 3.1 Users and SSH (1.5 marks)
# - Create deploy user and ops group
# - Add deploy to ops group
# - Disable root login and password authentication in sshd_config
# ------------------------------------------------------------------------------
echo "[1/4] Configuring users and groups (deploy user, ops group)..."
if ! getent group ops &>/dev/null; then
    groupadd ops
    echo "[OK] Created group 'ops'."
fi

if ! id -u deploy &>/dev/null; then
    useradd -m -s /bin/bash -g ops deploy
    echo "[OK] Created user 'deploy' with primary group 'ops'."
else
    usermod -aG ops deploy
    echo "[INFO] User 'deploy' already exists. Ensured membership in 'ops'."
fi

# Ensure shoplite user also exists for least-privilege container mapping
if ! id -u shoplite &>/dev/null; then
    useradd -m -s /bin/bash shoplite
    echo "[OK] Created service user 'shoplite'."
fi

echo "[1.1/4] Applying SSH Hardening..."
mkdir -p /etc/ssh/sshd_config.d
cp "${SCRIPT_DIR}/sshd_config" /etc/ssh/sshd_config.d/99-shoplite.conf
chmod 0644 /etc/ssh/sshd_config.d/99-shoplite.conf
if sshd -t; then
    echo "[OK] OpenSSH configuration validated successfully."
    systemctl reload ssh || systemctl reload sshd || true
else
    echo "[WARN] sshd -t validation failed. Reverting 99-shoplite.conf"
    rm -f /etc/ssh/sshd_config.d/99-shoplite.conf
fi

# ------------------------------------------------------------------------------
# 3.2 File Permissions & ACL (1 mark)
# - /var/log/shoplite/ readable by ops group only
# - Using chmod, chown, and exactly one setfacl rule
# ------------------------------------------------------------------------------
echo "[2/4] Setting up /var/log/shoplite/ permissions with setfacl..."
apt-get update -y -qq && apt-get install -y -qq acl || true

mkdir -p /var/log/shoplite
touch /var/log/shoplite/app.log

# Ownership to root:ops
chown -R root:ops /var/log/shoplite

# Restrict base permissions: Owner=rwx, Group=rx, Others=none
chmod 0750 /var/log/shoplite
chmod 0640 /var/log/shoplite/app.log

# Exactly ONE setfacl rule: grant default read/execute to ops group for any new files
setfacl -d -m g:ops:r-x /var/log/shoplite
echo "[OK] Applied chown root:ops, chmod 0750, and setfacl default rule on /var/log/shoplite."

# ------------------------------------------------------------------------------
# 3.3 systemd Backup Service & Timer (1.5 marks)
# - Nightly pg_dump backup of ShopLite DB
# - Stored under /var/backups/shoplite/
# - Restart=on-failure configured
# ------------------------------------------------------------------------------
echo "[3/4] Installing systemd backup service and timer..."
mkdir -p /opt/shoplite/scripts /var/backups/shoplite
cp "${SCRIPT_DIR}/systemd/backup-postgres.sh" /opt/shoplite/scripts/backup-postgres.sh
chmod 0750 /opt/shoplite/scripts/backup-postgres.sh

cp "${SCRIPT_DIR}/systemd/shoplite-backup.service" /etc/systemd/system/
cp "${SCRIPT_DIR}/systemd/shoplite-backup.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now shoplite-backup.timer
echo "[OK] shoplite-backup.timer armed and enabled."

# ------------------------------------------------------------------------------
# 3.4 Firewall Configuration (1 mark)
# ------------------------------------------------------------------------------
echo "[4/4] Configuring UFW firewall rules..."
if command -v ufw &>/dev/null; then
    bash "${SCRIPT_DIR}/firewall/ufw-rules.sh"
else
    echo "[INFO] UFW is not installed. Skipping firewall activation."
fi

echo "=========================================================="
echo "✅ Question 3 Linux Server Administration Setup Complete!"
echo "=========================================================="

