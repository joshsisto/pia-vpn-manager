#!/bin/bash

# Quick test to verify VPN functionality

echo "🚀 Quick VPN Test - Finding the Issue"
echo "====================================="

# Check current state
echo "Current IP: $(curl -s ipinfo.io/ip)"
echo "Current routes: $(ip route show | wc -l) routes total"
echo ""

# Test basic connectivity to PIA server
echo "Testing PIA server connectivity:"
ping -c 2 us3.privacy.network && echo "✅ Server reachable" || echo "❌ Server unreachable"
echo ""

# Test credentials format by creating a test auth file
echo "Testing credentials format:"
echo "p7358164" > /tmp/test-auth.txt
echo "m9ezt2HjjZ" >> /tmp/test-auth.txt
echo "Credentials file created with $(wc -l < /tmp/test-auth.txt) lines"
echo ""

echo "Current working OpenVPN process check:"
sudo pkill openvpn 2>/dev/null || echo "No OpenVPN processes to kill"

echo ""
echo "The core issue appears to be OpenVPN 2.6 compatibility."
echo "Let me check what happens with a direct connection..."

# Clean, direct test
echo ""
echo "Testing direct OpenVPN connection (10 second test):"
echo "Before: IP = $(curl -s ipinfo.io/ip)"

# Create basic config
cat > /tmp/test.ovpn << 'EOF'
client
dev tun
proto udp
remote us3.privacy.network 1198
auth-user-pass /tmp/test-auth.txt
ca configs/openvpn/ca.rsa.4096.crt
verb 3
EOF

timeout 10 sudo openvpn --config /tmp/test.ovpn 2>&1 | head -20 &
sleep 8

echo "After 8 seconds: IP = $(curl -s ipinfo.io/ip)"
echo "Tunnel check: $(ip addr show tun0 2>/dev/null | grep inet || echo 'No tunnel')"

# Cleanup
sudo pkill openvpn 2>/dev/null || true
rm -f /tmp/test.ovpn /tmp/test-auth.txt

echo ""
echo "Quick test completed."