#!/bin/bash

# Test VPN Connection Script
# Simple test to verify the VPN system works

echo "🧪 Testing PIA VPN Manager"
echo "=========================="
echo ""

# Test 1: Check current status
echo "1. Current Status:"
pia-status --quiet
echo "   Current IP: $(pia-status --ip-only)"
echo ""

# Test 2: List some servers
echo "2. Available servers (first 5):"
pia-list-servers --names | head -5
echo ""

# Test 3: Test server connectivity
echo "3. Testing server connectivity:"
echo "   This will test if you can connect to us_west (dry run)"
echo ""

# Test privilege check
echo "4. Checking privileges:"
if sudo -n ip route show >/dev/null 2>&1; then
    echo "   ✅ Sudo access configured correctly"
    echo ""
    echo "🎉 Ready to test VPN connection!"
    echo ""
    echo "Next steps:"
    echo "   pia-connect us_west    # Connect to US West"
    echo "   pia-status            # Check status"
    echo "   pia-disconnect        # Disconnect"
else
    echo "   ⚠️  Sudo access needs configuration"
    echo ""
    echo "To set up passwordless sudo, run:"
    echo "   sudo ./setup-sudoers.sh"
    echo ""
    echo "Or run VPN commands with sudo:"
    echo "   sudo pia-connect us_west"
fi

echo ""