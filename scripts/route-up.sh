#!/bin/bash

# PIA VPN Route-Up Script
# This script runs when the VPN connection is established
# It implements SSH/Tailscale protection and DNS configuration

# Get the script directory and load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/lib/common.sh"

# Initialize
init_common

log "INFO" "Route-up script started for VPN interface: $dev"
log "DEBUG" "VPN gateway: $route_vpn_gateway, Remote: $trusted_ip"

# Protection for SSH/Tailscale traffic (must be done before changing default route)
protect_ssh_routes "add"

# OpenVPN will handle basic routing, we just add our SSH protection
log "INFO" "VPN tunnel established, OpenVPN handled basic routing"

# Set VPN DNS servers
if [[ -n "$PIA_DNS_SERVERS" ]]; then
    set_vpn_dns "$PIA_DNS_SERVERS"
fi

# Log the new public IP
sleep 5  # Wait a moment for routing to stabilize
new_ip=$(get_public_ip)
log "INFO" "VPN connected - New public IP: $new_ip"

# Additional route protection for the original gateway
gateway_info=$(get_default_gateway_info)
original_gateway=${gateway_info%%:*}
original_interface=${gateway_info##*:}

if [[ -n "$original_gateway" ]] && [[ -n "$original_interface" ]]; then
    # Ensure we can still reach the VPN server through the original route
    if [[ -n "$trusted_ip" ]]; then
        ip route add "$trusted_ip" via "$original_gateway" dev "$original_interface" 2>/dev/null || true
        log "DEBUG" "Added route for VPN server $trusted_ip via original gateway"
    fi
fi

log "INFO" "Route-up script completed successfully"