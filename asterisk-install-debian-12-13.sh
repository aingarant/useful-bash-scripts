#!/bin/bash

set -e  # Exit on any error

echo "=========================================="
echo "Asterisk 22 Installation Script"
echo "Debian 12/13"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Update system
echo "[1/16] Updating system packages..."
apt update -y
apt upgrade -y
echo ""

# Install curl
echo "[2/16] Installing curl..."
apt install -y curl
echo ""

# Stop and remove AppArmor
echo "[3/16] Stopping AppArmor..."
systemctl stop apparmor || true
systemctl disable apparmor || true
echo ""

echo "[4/16] Removing AppArmor..."
apt remove -y apparmor
echo ""

# Download Asterisk
echo "[5/16] Navigating to /usr/src..."
cd /usr/src
echo ""

echo "[6/16] Downloading Asterisk 22..."
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22-current.tar.gz
echo ""

echo "[7/16] Extracting Asterisk..."
tar zxvf asterisk-22-current.tar.gz
rm -f asterisk-22-current.tar.gz
echo ""

# Find and enter Asterisk directory
ASTERISK_DIR=$(ls -d asterisk-22* | head -1)
echo "[8/16] Entering directory: $ASTERISK_DIR"
cd "$ASTERISK_DIR"
echo ""

# Install prerequisites
echo "[9/16] Installing prerequisites..."
contrib/scripts/install_prereq install
echo ""

# Configure
echo "[10/16] Running configure..."
./configure
echo ""

# Compile
echo "[11/16] Compiling (this may take a while)..."
make
echo ""

# Install
echo "[12/16] Installing Asterisk..."
make install
echo ""

# Install samples
echo "[13/16] Installing sample configurations..."
make samples
echo ""

# Backup original configs
echo "[14/16] Backing up original configurations..."
if [ ! -d /etc/asterisk/samples ]; then
    mkdir -p /etc/asterisk/samples
fi
find /etc/asterisk -maxdepth 1 -type f -name "*.*" -exec mv {} /etc/asterisk/samples/ \;
echo ""

# Install basic PBX and config
echo "[15/16] Installing basic PBX and configuration..."
make basic-pbx
make config
echo ""

# Enable and start service
echo "[16/16] Enabling and starting Asterisk service..."
systemctl daemon-reload
systemctl enable asterisk.service
systemctl start asterisk.service
echo ""

# Check status
echo "=========================================="
echo "Checking Asterisk service status..."
echo "=========================================="
systemctl status asterisk.service
echo ""

echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Connect Asterisk console by typing asterisk -rvvvv"
echo ""

