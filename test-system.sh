#!/bin/bash

# PIA VPN Manager System Test Script
# Tests key functionality without requiring VPN connection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/servers.sh"

echo "🧪 PIA VPN Manager System Test"
echo "==============================="
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo "✅ $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo "❌ $1"
    ((TESTS_FAILED++))
}

# Test 1: Environment loading
echo "Testing environment loading..."
if load_env >/dev/null 2>&1; then
    test_pass "Environment file loaded successfully"
else
    test_fail "Failed to load environment file"
fi

# Test 2: Server configuration
echo "Testing server configuration..."
if load_servers >/dev/null 2>&1; then
    test_pass "Server configuration loaded"
else
    test_fail "Failed to load server configuration"
fi

# Test 3: Server list functionality
echo "Testing server listing..."
server_count=$(list_all_servers | wc -l)
if [[ $server_count -gt 40 ]]; then
    test_pass "Server list contains $server_count servers"
else
    test_fail "Server list too small: $server_count servers"
fi

# Test 4: Server validation
echo "Testing server validation..."
if validate_server "us_west"; then
    test_pass "Server validation works for valid servers"
else
    test_fail "Server validation failed for valid server"
fi

if ! validate_server "invalid_server_123"; then
    test_pass "Server validation correctly rejects invalid servers"
else
    test_fail "Server validation incorrectly accepted invalid server"
fi

# Test 5: IP detection
echo "Testing IP detection..."
current_ip=$(get_public_ip)
if [[ -n "$current_ip" ]] && [[ "$current_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    test_pass "Public IP detection works: $current_ip"
else
    test_fail "Public IP detection failed: $current_ip"
fi

# Test 6: Tailscale detection
echo "Testing Tailscale detection..."
ts_info=$(get_tailscale_info)
if [[ -n "$ts_info" ]]; then
    ts_interface=${ts_info%%:*}
    ts_ip=${ts_info##*:}
    test_pass "Tailscale detected: $ts_interface ($ts_ip)"
else
    test_fail "Tailscale interface not detected"
fi

# Test 7: VPN status detection
echo "Testing VPN status detection..."
if is_vpn_connected; then
    current_server=$(get_current_vpn_server)
    test_pass "VPN connection detected: $current_server"
else
    test_pass "No VPN connection detected (as expected)"
fi

# Test 8: Certificate files
echo "Testing certificate files..."
if [[ -f "$PROJECT_DIR/configs/openvpn/ca.rsa.4096.crt" ]]; then
    test_pass "CA certificate file exists"
else
    test_fail "CA certificate file missing"
fi

if [[ -f "$PROJECT_DIR/configs/openvpn/crl.rsa.4096.pem" ]]; then
    test_pass "CRL file exists"
else
    test_fail "CRL file missing"
fi

# Test 9: Script executability
echo "Testing script permissions..."
scripts=("pia-connect.sh" "pia-disconnect.sh" "pia-status.sh" "pia-rotate.sh" "pia-list-servers.sh")
for script in "${scripts[@]}"; do
    if [[ -x "$PROJECT_DIR/$script" ]]; then
        test_pass "$script is executable"
    else
        test_fail "$script is not executable"
    fi
done

# Test 10: Configuration file security
echo "Testing configuration security..."
env_perms=$(stat -c "%a" "$PROJECT_DIR/.env" 2>/dev/null || echo "000")
if [[ "$env_perms" == "600" ]]; then
    test_pass ".env file has correct permissions (600)"
else
    test_fail ".env file has incorrect permissions: $env_perms"
fi

# Test 11: Connectivity test
echo "Testing basic connectivity..."
if check_connectivity; then
    test_pass "Internet connectivity confirmed"
else
    test_fail "No internet connectivity"
fi

# Test 12: DNS functionality
echo "Testing DNS resolution..."
if command -v dig >/dev/null 2>&1; then
    if dig +short google.com >/dev/null 2>&1; then
        test_pass "DNS resolution working"
    else
        test_fail "DNS resolution failed"
    fi
else
    test_pass "DNS test skipped (dig not available)"
fi

# Test 13: Required commands
echo "Testing required system commands..."
required_commands=("openvpn" "curl" "ip" "ping" "ps" "kill")
for cmd in "${required_commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        test_pass "Command '$cmd' available"
    else
        test_fail "Command '$cmd' not found"
    fi
done

# Test 14: Directory structure
echo "Testing directory structure..."
required_dirs=("configs" "configs/openvpn" "lib" "scripts" "logs")
for dir in "${required_dirs[@]}"; do
    if [[ -d "$PROJECT_DIR/$dir" ]]; then
        test_pass "Directory '$dir' exists"
    else
        test_fail "Directory '$dir' missing"
    fi
done

# Summary
echo ""
echo "==============================================="
echo "🏁 Test Summary"
echo "==============================================="
echo "✅ Tests passed: $TESTS_PASSED"
echo "❌ Tests failed: $TESTS_FAILED"
echo "📊 Total tests:  $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo ""
    echo "🎉 All tests passed! System is ready for use."
    echo ""
    echo "Next steps:"
    echo "1. Verify PIA credentials in .env file"
    echo "2. Test VPN connection: sudo ./pia-connect.sh us_west"
    echo "3. Check status: ./pia-status.sh"
    echo "4. Disconnect: sudo ./pia-disconnect.sh"
    exit 0
else
    echo ""
    echo "⚠️  Some tests failed. Please review the issues above."
    echo ""
    echo "Common solutions:"
    echo "- Run ./install.sh to install missing dependencies"
    echo "- Check internet connectivity"
    echo "- Verify .env file configuration"
    exit 1
fi