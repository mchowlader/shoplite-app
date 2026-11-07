#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Firewall Configuration Script
# Requirement 3.4: Allow inbound 22, 80, 443; Deny incoming by default
# ==============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run as root or with sudo." >&2
    exit 1
fi

echo "[INFO] Configuring UFW Firewall..."

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allowed ports
ufw limit 22/tcp comment 'SSH rate-limited (Question 3.4)'
ufw allow 80/tcp comment 'HTTP Web Frontend'
ufw allow 443/tcp comment 'HTTPS Secure Traffic'

# Enable firewall
ufw --force enable

echo "[SUCCESS] UFW Firewall active. Current status:"
ufw status verbose
