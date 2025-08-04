#!/bin/bash

# PIA VPN Status Script
# Shows current VPN status, connection details, and network information

set -euo pipefail

# Get the script directory and load libraries
# Handle both direct execution and symlinked execution
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}")")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/servers.sh"

# Help function
show_help() {
    cat << EOF
PIA VPN Status Script

Usage: $0 [OPTIONS]

Display current VPN status, connection details, and network information.

Options:
  -h, --help     Show this help message
  -v, --verbose  Show detailed information including routing and DNS
  -j, --json     Output status in JSON format
  -q, --quiet    Show only basic status (connected/disconnected)
  -i, --ip-only  Show only the current public IP address
  -t, --test     Test current connection (ping test and DNS leak check)

Examples:
  $0                    # Show basic VPN status
  $0 --verbose          # Show detailed network information
  $0 --json             # Output in JSON format for automation
  $0 --ip-only          # Show only current IP
  $0 --test             # Test connection quality

EOF
}

# Parse command line arguments
VERBOSE=false
JSON_OUTPUT=false
QUIET=false
IP_ONLY=false
TEST_CONNECTION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -i|--ip-only)
            IP_ONLY=true
            shift
            ;;
        -t|--test)
            TEST_CONNECTION=true
            shift
            ;;
        -*)
            echo "ERROR: Unknown option $1" >&2
            show_help
            exit 1
            ;;
        *)
            echo "ERROR: No arguments expected" >&2
            show_help
            exit 1
            ;;
    esac
done

# Initialize (but don't require root for status checks)
load_env || true
load_servers || true

# Get current public IP
CURRENT_IP=$(get_public_ip 2>/dev/null || echo "unavailable")

# IP-only output
if [[ "$IP_ONLY" == "true" ]]; then
    echo "$CURRENT_IP"
    exit 0
fi

# Check VPN status
VPN_CONNECTED=$(is_vpn_connected && echo "true" || echo "false")
CURRENT_SERVER=""
CURRENT_SERVER_DISPLAY=""
CURRENT_SERVER_HOSTNAME=""
CONNECTION_TIME=""
OPENVPN_PID=""

if [[ "$VPN_CONNECTED" == "true" ]]; then
    CURRENT_SERVER=$(get_current_vpn_server)
    if [[ -n "$CURRENT_SERVER" ]]; then
        CURRENT_SERVER_DISPLAY=$(get_server_display_name "$CURRENT_SERVER" 2>/dev/null || echo "$CURRENT_SERVER")
        CURRENT_SERVER_HOSTNAME=$(get_server_hostname "$CURRENT_SERVER" 2>/dev/null || echo "")
    fi
    
    # Get OpenVPN process info
    OPENVPN_PID=$(pgrep -f "openvpn.*pia" | head -1 || echo "")
    if [[ -n "$OPENVPN_PID" ]]; then
        # Get process start time
        if command -v ps >/dev/null; then
            CONNECTION_TIME=$(ps -o lstart= -p "$OPENVPN_PID" 2>/dev/null | xargs || echo "")
        fi
    fi
fi

# Get Tailscale info
TAILSCALE_INFO=$(get_tailscale_info || echo "")
TAILSCALE_INTERFACE=""
TAILSCALE_IP=""
if [[ -n "$TAILSCALE_INFO" ]]; then
    TAILSCALE_INTERFACE=${TAILSCALE_INFO%%:*}
    TAILSCALE_IP=${TAILSCALE_INFO##*:}
fi

# JSON output
if [[ "$JSON_OUTPUT" == "true" ]]; then
    cat << EOF
{
  "vpn_connected": $VPN_CONNECTED,
  "current_ip": "$CURRENT_IP",
  "server": {
    "name": "$CURRENT_SERVER",
    "display_name": "$CURRENT_SERVER_DISPLAY",
    "hostname": "$CURRENT_SERVER_HOSTNAME"
  },
  "connection": {
    "pid": "$OPENVPN_PID",
    "started": "$CONNECTION_TIME"
  },
  "tailscale": {
    "interface": "$TAILSCALE_INTERFACE",
    "ip": "$TAILSCALE_IP"
  }
}
EOF
    exit 0
fi

# Quiet output
if [[ "$QUIET" == "true" ]]; then
    if [[ "$VPN_CONNECTED" == "true" ]]; then
        echo "Connected"
    else
        echo "Disconnected"
    fi
    exit 0
fi

# Standard output
echo "=== PIA VPN Status ==="
echo ""

# VPN Connection Status
if [[ "$VPN_CONNECTED" == "true" ]]; then
    echo "Status: ✓ Connected"
    if [[ -n "$CURRENT_SERVER_DISPLAY" ]]; then
        echo "Server: $CURRENT_SERVER_DISPLAY"
        if [[ -n "$CURRENT_SERVER_HOSTNAME" ]]; then
            echo "Hostname: $CURRENT_SERVER_HOSTNAME"
        fi
    fi
    if [[ -n "$CONNECTION_TIME" ]]; then
        echo "Connected since: $CONNECTION_TIME"
    fi
    if [[ -n "$OPENVPN_PID" ]]; then
        echo "Process ID: $OPENVPN_PID"
    fi
else
    echo "Status: ✗ Disconnected"
fi

echo ""
echo "Public IP: $CURRENT_IP"

# Tailscale status
if [[ -n "$TAILSCALE_IP" ]]; then
    echo "Tailscale IP: $TAILSCALE_IP ($TAILSCALE_INTERFACE)"
fi

# Verbose information
if [[ "$VERBOSE" == "true" ]]; then
    echo ""
    echo "=== Network Details ==="
    
    # DNS servers
    echo ""
    echo "DNS Configuration:"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl status | grep -E "(DNS Servers|Current DNS)" | head -5 || echo "  DNS info unavailable"
    else
        cat /etc/resolv.conf | grep nameserver | head -3 || echo "  DNS info unavailable"
    fi
    
    # Route information
    echo ""
    echo "Default Route:"
    ip route show default | head -1 || echo "  No default route found"
    
    # VPN interface info
    if [[ "$VPN_CONNECTED" == "true" ]]; then
        echo ""
        echo "VPN Interface:"
        ip addr show tun0 2>/dev/null | grep -E "(inet|state)" || echo "  VPN interface not found"
    fi
    
    # OpenVPN log (last few lines)
    if [[ "$VPN_CONNECTED" == "true" && -n "$CURRENT_SERVER" ]]; then
        local log_file="$PROJECT_DIR/logs/openvpn-${CURRENT_SERVER}.log"
        if [[ -f "$log_file" ]]; then
            echo ""
            echo "Recent OpenVPN Log:"
            tail -5 "$log_file" | sed 's/^/  /'
        fi
    fi
fi

# Connection testing
if [[ "$TEST_CONNECTION" == "true" ]]; then
    echo ""
    echo "=== Connection Test ==="
    
    if [[ "$VPN_CONNECTED" == "true" ]]; then
        # Test latency to current server
        if [[ -n "$CURRENT_SERVER_HOSTNAME" ]]; then
            echo ""
            echo "Server latency test:"
            if ping -c 3 -W 2 "$CURRENT_SERVER_HOSTNAME" >/dev/null 2>&1; then
                latency=$(ping -c 3 -W 2 "$CURRENT_SERVER_HOSTNAME" 2>/dev/null | grep "time=" | tail -1 | grep -o "time=[0-9.]*" | cut -d'=' -f2)
                echo "  ✓ $CURRENT_SERVER_HOSTNAME: ${latency}ms"
            else
                echo "  ✗ Cannot reach VPN server"
            fi
        fi
        
        # DNS leak test
        echo ""
        echo "DNS leak test:"
        if command -v dig >/dev/null 2>&1; then
            dns_ip=$(dig +short @8.8.8.8 o-o.myaddr.l.google.com TXT 2>/dev/null | tr -d '"' || echo "")
            if [[ -n "$dns_ip" ]]; then
                if [[ "$dns_ip" == "$CURRENT_IP" ]]; then
                    echo "  ✓ No DNS leak detected"
                else
                    echo "  ⚠ Potential DNS leak: $dns_ip vs $CURRENT_IP"
                fi
            else
                echo "  ? Cannot perform DNS leak test"
            fi
        else
            echo "  ? dig command not available for DNS leak test"
        fi
        
        # General connectivity test
        echo ""
        echo "Internet connectivity:"
        if check_connectivity; then
            echo "  ✓ Internet access working"
        else
            echo "  ✗ No internet connectivity"
        fi
        
    else
        echo ""
        echo "VPN not connected - skipping connection tests"
    fi
fi

echo ""