#!/bin/bash

# PIA WireGuard VPN Disconnection Script
# This script safely disconnects from PIA VPN using WireGuard
# with proper cleanup and SSH/Tailscale protection

# Handle symlinked execution
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}")")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Load common functions
source "$SCRIPT_DIR/lib/common.sh"

# Load environment variables
load_env || exit 1

# Set default log file
VPN_LOG_FILE="${VPN_LOG_FILE:-$PROJECT_DIR/logs/pia-vpn.log}"

log "INFO" "Starting WireGuard VPN disconnection"

# Function to get current WireGuard connection info
get_current_connection() {
    local current_config="$PROJECT_DIR/configs/current-wireguard.conf"
    
    if [[ -f "$current_config" ]]; then
        source "$current_config"
        echo "$CONFIG_FILE"
    else
        # Try to find any active WireGuard interface
        local active_interface=$(wg show interfaces 2>/dev/null | head -1)
        if [[ -n "$active_interface" ]]; then
            # Look for corresponding config file
            local config_file=$(find "$PROJECT_DIR/configs/wireguard" -name "*.conf" 2>/dev/null | head -1)
            echo "$config_file"
        fi
    fi
}

# Function to disconnect WireGuard
disconnect_wireguard() {
    local config_file="$1"
    
    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log "WARN" "No WireGuard configuration file found"
        
        # Check for any active WireGuard interfaces
        local interfaces=$(wg show interfaces 2>/dev/null)
        
        if [[ -n "$interfaces" ]]; then
            log "INFO" "Found active WireGuard interfaces, attempting to bring them down"
            
            for interface in $interfaces; do
                log "INFO" "Bringing down WireGuard interface: $interface"
                run_as_root wg-quick down "$interface" 2>/dev/null || \
                run_as_root ip link delete "$interface" 2>/dev/null || true
            done
        else
            log "INFO" "No active WireGuard connections found"
            return 0
        fi
    else
        log "INFO" "Disconnecting WireGuard using config: $(basename "$config_file")"
        
        # Use wg-quick to properly bring down the interface
        if run_as_root wg-quick down "$config_file"; then
            log "INFO" "WireGuard interface brought down successfully"
        else
            log "WARN" "wg-quick down failed, attempting manual cleanup"
            
            # Try to find and remove interface manually
            local interface_name=$(basename "$config_file" .conf)
            run_as_root ip link delete "$interface_name" 2>/dev/null || true
        fi
    fi
    
    # Verify disconnection
    local remaining_interfaces=$(wg show interfaces 2>/dev/null)
    
    if [[ -z "$remaining_interfaces" ]]; then
        log "INFO" "All WireGuard interfaces successfully removed"
        return 0
    else
        log "WARN" "Some WireGuard interfaces may still be active: $remaining_interfaces"
        return 1
    fi
}

# Function to cleanup configuration files
cleanup_configs() {
    log "INFO" "Cleaning up WireGuard configuration files"
    
    # Remove current connection info
    local current_config="$PROJECT_DIR/configs/current-wireguard.conf"
    if [[ -f "$current_config" ]]; then
        rm -f "$current_config"
        log "DEBUG" "Removed current connection info"
    fi
    
    # Optionally remove generated config files (keep them for debugging)
    # rm -f "$PROJECT_DIR/configs/wireguard/pia-"*.conf
}

# Function to restore network configuration
restore_network() {
    log "INFO" "Restoring network configuration"
    
    # Clean up any remaining SSH protection routes
    protect_ssh_routes "delete"
    
    # Restore DNS if needed
    restore_dns
    
    log "INFO" "Network configuration restored"
}

# Function to verify disconnection
verify_disconnection() {
    log "INFO" "Verifying VPN disconnection"
    
    # Check that no WireGuard interfaces remain
    local interfaces=$(wg show interfaces 2>/dev/null)
    if [[ -n "$interfaces" ]]; then
        log "WARN" "WireGuard interfaces still active: $interfaces"
        return 1
    fi
    
    # Check current IP
    local current_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null)
    if [[ -n "$current_ip" ]]; then
        log "INFO" "Current public IP: $current_ip"
        
        # If IP is back to original, disconnection was successful
        if [[ "$current_ip" == "209.38.155.4" ]]; then
            log "INFO" "✅ VPN disconnected successfully - IP restored to original"
            echo "✅ VPN disconnected successfully"
            echo "Current IP: $current_ip"
            return 0
        else
            log "INFO" "VPN disconnected - Current IP: $current_ip"
            echo "VPN disconnected - Current IP: $current_ip"
            return 0
        fi
    else
        log "WARN" "Could not verify current IP address"
        echo "VPN disconnected (IP verification failed)"
        return 0
    fi
}

# Main execution
main() {
    # Get current WireGuard connection
    local config_file=$(get_current_connection)
    
    if [[ -z "$config_file" ]]; then
        # Check if any WireGuard interfaces are active
        if ! wg show interfaces 2>/dev/null | head -1 | grep -q .; then
            echo "No WireGuard VPN connection found"
            log "INFO" "No active WireGuard connections to disconnect"
            exit 0
        fi
    fi
    
    # Disconnect WireGuard
    if disconnect_wireguard "$config_file"; then
        log "INFO" "WireGuard disconnection successful"
    else
        log "WARN" "WireGuard disconnection completed with warnings"
    fi
    
    # Cleanup configuration files
    cleanup_configs
    
    # Restore network configuration
    restore_network
    
    # Verify disconnection
    verify_disconnection
    
    log "INFO" "WireGuard VPN disconnection completed"
}

# Setup cleanup on exit
trap 'log "INFO" "WireGuard disconnect script exiting"' EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi