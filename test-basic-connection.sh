#!/bin/bash

# Basic VPN connection test without our custom scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

echo "🧪 Testing basic OpenVPN connection"
echo "=================================="

# Initialize
load_env

# Create a basic test config without our scripts
TEST_CONFIG="/tmp/test-pia.ovpn"
AUTH_FILE="$SCRIPT_DIR/configs/openvpn/auth.txt"

echo "Creating basic test configuration..."

# Copy the PIA config and modify it to remove our custom scripts
cp us_west.ovpn "$TEST_CONFIG"

# Remove our custom scripts from the config
sed -i '/route-up.sh/d' "$TEST_CONFIG"
sed -i '/route-down.sh/d' "$TEST_CONFIG"
sed -i '/script-security/d' "$TEST_CONFIG"

# Ensure auth file points to correct location
sed -i "s|auth-user-pass.*|auth-user-pass $AUTH_FILE|" "$TEST_CONFIG"

echo "Original IP: $(curl -s ipinfo.io/ip)"
echo ""
echo "Starting OpenVPN test (will run for 30 seconds)..."

# Create credentials file
echo "$PIA_USERNAME" > "$AUTH_FILE"
echo "$PIA_PASSWORD" >> "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

# Run OpenVPN with timeout
timeout 30 sudo openvpn --config "$TEST_CONFIG" --verb 3 || true

echo ""
echo "Test completed. Checking IP after test..."
echo "Current IP: $(curl -s ipinfo.io/ip)"

# Cleanup
rm -f "$TEST_CONFIG"

echo "Basic connection test finished."