#!/bin/bash

# Test script to verify WireGuard setup is ready
# This tests everything up to the point where sudo is needed

echo "🧪 Testing WireGuard VPN Setup (Pre-Sudo)"
echo "========================================"

source lib/common.sh 2>/dev/null
load_env 2>/dev/null

echo "✅ 1. Environment loaded"

# Test authentication
echo -n "⏳ 2. Testing PIA authentication... "
source pia-wg-connect.sh 2>/dev/null
token=$(_get_pia_token_raw "$PIA_USERNAME" "$PIA_PASSWORD")
if [[ -n "$token" && ${#token} -eq 128 ]]; then
    echo "✅ SUCCESS"
else
    echo "❌ FAILED"
    exit 1
fi

# Test server info
echo -n "⏳ 3. Testing server information... "
server_info=$(get_server_info "us_west" 2>/dev/null)
if [[ -n "$server_info" ]]; then
    hostname=$(echo "$server_info" | cut -d'|' -f1)
    server_ip=$(echo "$server_info" | cut -d'|' -f2)
    echo "✅ SUCCESS ($hostname)"
else
    echo "❌ FAILED"
    exit 1
fi

# Test WireGuard key generation
echo -n "⏳ 4. Testing WireGuard key generation... "
private_key=$(wg genkey 2>/dev/null)
public_key=$(echo "$private_key" | wg pubkey 2>/dev/null)
if [[ -n "$private_key" && -n "$public_key" ]]; then
    echo "✅ SUCCESS"
else
    echo "❌ FAILED"
    exit 1
fi

# Test WireGuard API
echo -n "⏳ 5. Testing WireGuard API... "
api_response=$(curl -s -G \
    --connect-to "$hostname::$server_ip:" \
    --cacert "configs/ca.rsa.4096.crt" \
    --data-urlencode "pt=$token" \
    --data-urlencode "pubkey=$public_key" \
    "https://$hostname:1337/addKey" 2>/dev/null)

status=$(echo "$api_response" | jq -r '.status // empty' 2>/dev/null)
if [[ "$status" == "OK" ]]; then
    echo "✅ SUCCESS"
    peer_ip=$(echo "$api_response" | jq -r '.peer_ip' 2>/dev/null)
    server_key=$(echo "$api_response" | jq -r '.server_key' 2>/dev/null)
    echo "   📋 WireGuard config data received:"
    echo "      Peer IP: $peer_ip"
    echo "      Server Key: ${server_key:0:20}..."
else
    echo "❌ FAILED"
    echo "   Response: $api_response"
    exit 1
fi

# Test certificate
echo -n "⏳ 6. Testing certificate file... "
if [[ -f "configs/ca.rsa.4096.crt" ]]; then
    echo "✅ SUCCESS"
else
    echo "❌ FAILED"
    exit 1
fi

echo ""
echo "🎉 ALL PRE-SUDO TESTS PASSED!"
echo ""
echo "📋 Ready for final setup:"
echo "   1. Run: sudo ./setup-sudoers.sh"
echo "   2. Test: ./pia-wg-connect.sh us_west"
echo ""
echo "🔒 SSH Status: Connected via Tailscale ($(ip addr show tailscale0 | grep inet | awk '{print $2}' | cut -d'/' -f1))"