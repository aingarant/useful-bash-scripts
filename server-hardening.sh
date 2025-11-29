#!/bin/bash

#############################################
# SSH Hardening & UFW Configuration Script
# Compatible with: Debian 12, 13, Ubuntu 22, 24
#############################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Backup function
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d-%H%M%S)"
        echo -e "${GREEN}✓${NC} Backed up $file"
    fi
}

# Display banner
echo -e "${GREEN}"
echo "=========================================="
echo "  SSH Hardening & UFW Configuration"
echo "=========================================="
echo -e "${NC}"

# Prompt for SSH port
while true; do
    read -p "Enter custom SSH port (1024-65535, recommended: 2222-9999): " SSH_PORT
    
    # Validate port number
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1024 ] && [ "$SSH_PORT" -le 65535 ]; then
        echo -e "${GREEN}✓${NC} Valid port number: $SSH_PORT"
        break
    else
        echo -e "${RED}✗${NC} Invalid port. Please enter a number between 1024 and 65535"
    fi
done

# Confirm settings
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  - SSH Port: $SSH_PORT"
echo "  - Root login: Disabled"
echo "  - Password authentication: Disabled"
echo "  - Public key authentication: Enabled"
echo "  - UFW: Enabled (only SSH port $SSH_PORT allowed)"
echo "  - Fail2ban: Enabled (SSH protection)"
echo ""
read -p "Continue with these settings? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted by user${NC}"
    exit 1
fi

# Install UFW if not present
echo ""
echo -e "${YELLOW}[1/8]${NC} Checking UFW installation..."
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW..."
    apt-get update -qq
    apt-get install -y ufw
    echo -e "${GREEN}✓${NC} UFW installed"
else
    echo -e "${GREEN}✓${NC} UFW already installed"
fi

# Install fail2ban if not present
echo ""
echo -e "${YELLOW}[2/8]${NC} Checking fail2ban installation..."
if ! command -v fail2ban-client &> /dev/null; then
    echo "Installing fail2ban..."
    apt-get install -y fail2ban
    echo -e "${GREEN}✓${NC} fail2ban installed"
else
    echo -e "${GREEN}✓${NC} fail2ban already installed"
fi

# Backup SSH config
echo ""
echo -e "${YELLOW}[3/8]${NC} Backing up SSH configuration..."
backup_file /etc/ssh/sshd_config

# Configure SSH
echo ""
echo -e "${YELLOW}[4/8]${NC} Configuring SSH..."

SSHD_CONFIG="/etc/ssh/sshd_config"

# Function to update or add SSH config directive
update_ssh_config() {
    local directive=$1
    local value=$2
    
    if grep -q "^#*${directive}" "$SSHD_CONFIG"; then
        # Directive exists (commented or not), replace it
        sed -i "s/^#*${directive}.*/${directive} ${value}/" "$SSHD_CONFIG"
    else
        # Directive doesn't exist, add it
        echo "${directive} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Apply SSH hardening settings
update_ssh_config "Port" "$SSH_PORT"
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PubkeyAuthentication" "yes"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UsePAM" "yes"
update_ssh_config "X11Forwarding" "no"
update_ssh_config "PrintMotd" "no"
update_ssh_config "AcceptEnv" "LANG LC_*"

echo -e "${GREEN}✓${NC} SSH configuration updated"

# Test SSH configuration
echo ""
echo -e "${YELLOW}[5/8]${NC} Testing SSH configuration..."
if sshd -t; then
    echo -e "${GREEN}✓${NC} SSH configuration is valid"
else
    echo -e "${RED}✗${NC} SSH configuration has errors. Restoring backup..."
    mv "${SSHD_CONFIG}.backup."* "$SSHD_CONFIG"
    echo -e "${RED}Configuration restored. Exiting.${NC}"
    exit 1
fi

# Configure UFW
echo ""
echo -e "${YELLOW}[6/8]${NC} Configuring UFW..."

# Reset UFW to default state
ufw --force reset > /dev/null 2>&1

# Set default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH on custom port
ufw allow "$SSH_PORT"/tcp comment 'SSH'

echo -e "${GREEN}✓${NC} UFW rules configured"

# Configure fail2ban
echo ""
echo -e "${YELLOW}[7/8]${NC} Configuring fail2ban..."

# Backup fail2ban config if it exists
backup_file /etc/fail2ban/jail.local

# Create jail.local with SSH protection
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Ban hosts for 1 hour:
bantime = 3600

# A host is banned if it has generated "maxretry" during the last "findtime"
findtime = 600

# "maxretry" is the number of failures before a host get banned.
maxretry = 5

# Destination email for alerts
destemail = root@localhost
sender = root@localhost

# Action to take when threshold is reached
action = %(action_)s

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

echo -e "${GREEN}✓${NC} fail2ban configuration created"

# Enable and start fail2ban
systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban

echo -e "${GREEN}✓${NC} fail2ban enabled and started"

# Enable UFW
echo ""
echo -e "${YELLOW}[8/8]${NC} Enabling UFW and restarting SSH..."

# Enable UFW
echo "y" | ufw enable > /dev/null 2>&1

echo -e "${GREEN}✓${NC} UFW enabled"

# Restart SSH service
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

echo -e "${GREEN}✓${NC} SSH service restarted"

# Display final status
echo ""
echo -e "${GREEN}=========================================="
echo "  Configuration Complete!"
echo "==========================================${NC}"
echo ""
echo -e "${YELLOW}Important Information:${NC}"
echo "  • SSH is now listening on port: ${GREEN}$SSH_PORT${NC}"
echo "  • Root login is: ${RED}DISABLED${NC}"
echo "  • Password authentication is: ${RED}DISABLED${NC}"
echo "  • Public key authentication is: ${GREEN}ENABLED${NC}"
echo ""
echo -e "${YELLOW}Firewall Status:${NC}"
ufw status verbose
echo ""
echo -e "${YELLOW}Fail2ban Status:${NC}"
fail2ban-client status sshd
echo ""
echo -e "${RED}⚠ WARNING:${NC} Make sure you have:"
echo "  1. Your SSH public key added to ~/.ssh/authorized_keys for your user"
echo "  2. Tested SSH connection on port $SSH_PORT BEFORE logging out"
echo ""
echo -e "${YELLOW}Test your connection with:${NC}"
echo "  ssh -p $SSH_PORT user@your_server_ip"
echo ""
echo -e "${GREEN}Backups created:${NC}"
ls -lh /etc/ssh/sshd_config.backup.* 2>/dev/null | tail -1
echo ""
echo -e "${YELLOW}Fail2ban Protection:${NC}"
echo "  • Max retries: 5 attempts"
echo "  • Ban time: 1 hour"
echo "  • Find time: 10 minutes"
echo "  • Monitoring: /var/log/auth.log"
echo ""
echo -e "${YELLOW}Useful fail2ban commands:${NC}"
echo "  • Check status: ${GREEN}sudo fail2ban-client status sshd${NC}"
echo "  • Unban an IP: ${GREEN}sudo fail2ban-client set sshd unbanip <IP>${NC}"
echo "  • Show banned IPs: ${GREEN}sudo fail2ban-client status sshd${NC}"
echo ""