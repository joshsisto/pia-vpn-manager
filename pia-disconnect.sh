#!/bin/bash

# PIA VPN Disconnect Script
# Safely disconnects from PIA VPN and restores original network configuration

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
PIA VPN Disconnect Script

Usage: $0 [OPTIONS]

Safely disconnect from PIA VPN and restore original network configuration.

Options:
  -h, --help     Show this help message
  -f, --force    Force disconnect (kill all OpenVPN processes)
  -q, --quiet    Suppress informational output
  -s, --status   Show disconnection status and IP verification

Examples:
  $0                    # Normal disconnect
  $0 --force            # Force disconnect all VPN connections
  $0 --status           # Show status after disconnect

EOF
}

# Parse command line arguments
FORCE_DISCONNECT=false
QUIET=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_DISCONNECT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -s|--status)
            SHOW_STATUS=true
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

# Initialize common functions
# Note: We don't use init_common here because during disconnection
# the .env file might not be accessible, and we still want to clean up
load_env || true
check_privileges || true  # Allow disconnect even without sudo access

# Check if VPN is currently connected
if ! is_vpn_connected; then
    if [[ "$QUIET" != "true" ]]; then
        echo "No VPN connection found"
        if [[ "$SHOW_STATUS" == "true" ]]; then
            current_ip=$(get_public_ip)
            echo "Current public IP: $current_ip"
        fi
    fi
    exit 0
fi

# Get current server info before disconnecting
CURRENT_SERVER=$(get_current_vpn_server)
if [[ -n "$CURRENT_SERVER" ]]; then
    CURRENT_DISPLAY=$(get_server_display_name "$CURRENT_SERVER" 2>/dev/null || echo "$CURRENT_SERVER")
    [[ "$QUIET" != "true" ]] && log "INFO" "Disconnecting from $CURRENT_DISPLAY..."
else
    [[ "$QUIET" != "true" ]] && log "INFO" "Disconnecting from VPN..."
fi

# Get current IP for comparison
ORIGINAL_IP=$(get_public_ip 2>/dev/null || echo "unknown")

# Disconnect from VPN
if [[ "$FORCE_DISCONNECT" == "true" ]]; then
    log "INFO" "Force disconnecting all VPN connections..."
    kill_openvpn
else
    log "INFO" "Gracefully disconnecting VPN..."
    
    # Try graceful shutdown first
    if [[ -f /var/run/openvpn-pia.pid ]]; then
        pid=$(cat /var/run/openvpn-pia.pid 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null; then
            log "DEBUG" "Sent TERM signal to OpenVPN process $pid"
            
            # Wait for graceful shutdown
            count=0
            while [[ $count -lt 10 ]] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                ((count++))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log "WARN" "Graceful shutdown timed out, force killing..."
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f /var/run/openvpn-pia.pid
    fi
    
    # Fallback: kill any remaining OpenVPN processes
    kill_openvpn
fi

# Wait for disconnection to complete
log "INFO" "Waiting for VPN disconnection to complete..."
DISCONNECT_ATTEMPTS=0
MAX_DISCONNECT_ATTEMPTS=15

while [[ $DISCONNECT_ATTEMPTS -lt $MAX_DISCONNECT_ATTEMPTS ]]; do
    if ! is_vpn_connected; then
        break
    fi
    sleep 1
    ((DISCONNECT_ATTEMPTS++))
done

# Restore network configuration
log "INFO" "Restoring network configuration..."

# Remove SSH/Tailscale protection routes
protect_ssh_routes "delete" 2>/dev/null || true

# Restore DNS configuration
restore_dns

# Wait for network to stabilize
sleep 3

# Verify disconnection
if is_vpn_connected; then
    log "ERROR" "Failed to disconnect VPN completely"
    if [[ "$QUIET" != "true" ]]; then
        echo "Some VPN processes may still be running. Try using --force option."
    fi
    exit 1
fi

# Get new IP and verify disconnection
NEW_IP=$(get_public_ip 2>/dev/null || echo "unknown")

if [[ "$QUIET" != "true" ]]; then
    echo "✓ Successfully disconnected from VPN"
    
    if [[ "$SHOW_STATUS" == "true" ]] || [[ "$ORIGINAL_IP" != "unknown" && "$NEW_IP" != "unknown" ]]; then
        if [[ "$ORIGINAL_IP" != "$NEW_IP" ]]; then
            log "INFO" "IP changed from $ORIGINAL_IP to $NEW_IP"
        fi
        echo "Current public IP: $NEW_IP"
    fi
fi

log "INFO" "VPN disconnection completed successfully"

# Clean up any remaining VPN-related files
rm -f /var/run/openvpn-pia.pid 2>/dev/null || true

exit 0