#!/bin/bash

# Setup Sudoers Script for PIA VPN Manager
# Run this script to configure passwordless sudo for VPN operations

echo "Setting up sudoers configuration for PIA VPN Manager..."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root:"
    echo "sudo $0"
    exit 1
fi

# Create sudoers file
cat > /etc/sudoers.d/pia-vpn << 'EOF'
# Sudoers configuration for PIA VPN Manager
# Allow josh user to run VPN-related commands without password

# Network configuration commands needed for VPN
josh ALL=(root) NOPASSWD: /sbin/ip
josh ALL=(root) NOPASSWD: /bin/ip
josh ALL=(root) NOPASSWD: /usr/sbin/openvpn
josh ALL=(root) NOPASSWD: /usr/bin/openvpn
josh ALL=(root) NOPASSWD: /bin/kill
josh ALL=(root) NOPASSWD: /usr/bin/kill
josh ALL=(root) NOPASSWD: /usr/bin/pkill
josh ALL=(root) NOPASSWD: /bin/pkill
josh ALL=(root) NOPASSWD: /bin/systemctl restart systemd-resolved
josh ALL=(root) NOPASSWD: /usr/bin/systemctl restart systemd-resolved
josh ALL=(root) NOPASSWD: /usr/bin/tee /etc/systemd/resolved.conf
josh ALL=(root) NOPASSWD: /bin/cp
josh ALL=(root) NOPASSWD: /bin/rm

# WireGuard commands
josh ALL=(root) NOPASSWD: /usr/bin/wg
josh ALL=(root) NOPASSWD: /usr/bin/wg-quick
josh ALL=(root) NOPASSWD: /usr/bin/tee
EOF

# Set proper permissions
chmod 440 /etc/sudoers.d/pia-vpn

# Validate sudoers syntax
if visudo -c -f /etc/sudoers.d/pia-vpn; then
    echo "✅ Sudoers configuration installed successfully!"
    echo ""
    echo "You can now run VPN commands without sudo:"
    echo "  pia-connect us_west"
    echo "  pia-status"
    echo "  pia-rotate"
    echo "  pia-disconnect"
else
    echo "❌ Sudoers configuration has syntax errors!"
    rm -f /etc/sudoers.d/pia-vpn
    exit 1
fi