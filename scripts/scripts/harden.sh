#!/usr/bin/env bash
# Basic Ubuntu server hardening. Run as root: sudo ./harden.sh
# SAFE TO RE-RUN (idempotent). Keep your current SSH session open until you test a NEW one.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "==> 1/6 Update packages"
apt-get update -y
apt-get upgrade -y

echo "==> 2/6 Install security tools"
apt-get install -y ufw fail2ban unattended-upgrades

echo "==> 3/6 Automatic security updates"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> 4/6 SSH hardening (keys only, no root login)"
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'CONF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
CONF
sshd -t                     # validate config BEFORE reloading
systemctl reload ssh

echo "==> 5/6 Firewall (allow SSH first, so you do not lock yourself out)"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> 6/6 Fail2ban"
systemctl enable --now fail2ban

echo "Done. Test a NEW ssh session now before closing this one."
ufw status verbose
