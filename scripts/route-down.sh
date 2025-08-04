#!/bin/bash

# PIA VPN Route-Down Script
# This script runs when the VPN connection is terminated
# It restores original routing and DNS configuration

# Get the script directory and load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize (but don't exit on credential validation failure during cleanup)
load_env || true

log "INFO" "Route-down script started for VPN interface: $dev"

# Restore original default route
gateway_info=$(get_default_gateway_info)
if [[ -n "$gateway_info" ]] && [[ "$gateway_info" != ":" ]]; then
    original_gateway=${gateway_info%%:*}
    original_interface=${gateway_info##*:}
    
    if [[ -n "$original_gateway" ]] && [[ -n "$original_interface" ]]; then
        log "INFO" "Restoring original default route via $original_gateway dev $original_interface"
        run_as_root ip route del default 2>/dev/null || true
        run_as_root ip route add default via "$original_gateway" dev "$original_interface" 2>/dev/null || true
    fi
fi

# Remove SSH/Tailscale protection routes
protect_ssh_routes "delete"

# Restore original DNS configuration
restore_dns

# Log the restored public IP
sleep 2  # Wait a moment for routing to stabilize
restored_ip=$(get_public_ip)
log "INFO" "VPN disconnected - Restored public IP: $restored_ip"

log "INFO" "Route-down script completed successfully"