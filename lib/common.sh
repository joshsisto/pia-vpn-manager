#!/bin/bash

# PIA VPN Manager - Common Functions Library
# This file contains shared functions used across all PIA VPN scripts

# Get the library directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# Load environment variables
load_env() {
    local env_file="$PROJECT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        # Export variables from .env file
        set -a
        source "$env_file"
        set +a
    else
        echo "ERROR: .env file not found at $env_file"
        echo "Please copy .env.template to .env and configure your credentials"
        return 1
    fi
}

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$VPN_LOG_FILE")"
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$VPN_LOG_FILE"
    
    # Also log to stdout based on log level
    case "$level" in
        ERROR)
            echo "ERROR: $message" >&2
            ;;
        WARN)
            echo "WARNING: $message"
            ;;
        INFO)
            if [[ "$VPN_LOG_LEVEL" == "info" ]] || [[ "$VPN_LOG_LEVEL" == "debug" ]]; then
                echo "INFO: $message"
            fi
            ;;
        DEBUG)
            if [[ "$VPN_LOG_LEVEL" == "debug" ]]; then
                echo "DEBUG: $message"
            fi
            ;;
    esac
}

# Check if we can run privileged commands
check_privileges() {
    # Test if we can run ip command with sudo
    if ! sudo -n ip route show >/dev/null 2>&1; then
        log "ERROR" "Cannot run network commands with sudo"
        log "INFO" "Configure passwordless sudo or run: sudo visudo"
        return 1
    fi
    return 0
}

# Run command with sudo if not root
run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Get current public IP
get_public_ip() {
    local ip
    ip=$(curl -s --connect-timeout 10 ipinfo.io/ip || curl -s --connect-timeout 10 icanhazip.com || curl -s --connect-timeout 10 ifconfig.me)
    echo "$ip"
}

# Check if Tailscale interface exists and get its IP
get_tailscale_info() {
    local ts_interface=$(ip link show | grep -o 'tailscale[0-9]*' | head -1)
    if [[ -n "$ts_interface" ]]; then
        local ts_ip=$(ip addr show "$ts_interface" | grep -oP 'inet \K[0-9.]+')
        echo "$ts_interface:$ts_ip"
    else
        echo ""
    fi
}

# Protect SSH/Tailscale traffic from VPN routing
protect_ssh_routes() {
    local action="$1"  # add or delete
    
    log "INFO" "Managing SSH protection routes: $action"
    
    # Get Tailscale info
    local ts_info=$(get_tailscale_info)
    if [[ -z "$ts_info" ]]; then
        log "WARN" "Tailscale interface not found - SSH protection may not work"
        return 1
    fi
    
    local ts_interface=${ts_info%%:*}
    local ts_ip=${ts_info##*:}
    
    log "DEBUG" "Tailscale interface: $ts_interface, IP: $ts_ip"
    
    if [[ "$action" == "add" ]]; then
        # Add routes to protect Tailscale traffic
        
        # Protect the entire Tailscale subnet
        run_as_root ip route add 100.64.0.0/10 dev "$ts_interface" table main 2>/dev/null || true
        
        # Add specific rule for Tailscale traffic
        run_as_root ip rule add from "$ts_ip" table main priority 100 2>/dev/null || true
        run_as_root ip rule add to 100.64.0.0/10 table main priority 100 2>/dev/null || true
        
        # Protect current SSH connections by preserving routes to active SSH sources
        local ssh_connections=$(netstat -tn | grep :22 | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort -u)
        for ssh_ip in $ssh_connections; do
            if [[ "$ssh_ip" != "$ts_ip" ]] && [[ "$ssh_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                local gateway=$(ip route get "$ssh_ip" | grep -oP 'via \K[0-9.]+' | head -1)
                local device=$(ip route get "$ssh_ip" | grep -oP 'dev \K\w+' | head -1)
                if [[ -n "$gateway" ]] && [[ -n "$device" ]]; then
                    run_as_root ip route add "$ssh_ip" via "$gateway" dev "$device" table main 2>/dev/null || true
                    log "DEBUG" "Protected SSH connection from $ssh_ip via $gateway dev $device"
                fi
            fi
        done
        
    elif [[ "$action" == "delete" ]]; then
        # Remove SSH protection routes
        run_as_root ip rule del from "$ts_ip" table main priority 100 2>/dev/null || true
        run_as_root ip rule del to 100.64.0.0/10 table main priority 100 2>/dev/null || true
        
        log "INFO" "SSH protection routes removed"
    fi
}

# Check if VPN is currently connected
is_vpn_connected() {
    if pgrep -f "openvpn.*pia" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Get current VPN server name from running process
get_current_vpn_server() {
    local config_file=$(ps aux | grep openvpn | grep -o '/[^[:space:]]*.ovpn' | head -1)
    if [[ -n "$config_file" ]]; then
        basename "$config_file" .ovpn
    else
        echo ""
    fi
}

# Kill all OpenVPN processes
kill_openvpn() {
    log "INFO" "Stopping all OpenVPN processes"
    run_as_root pkill -f openvpn || true
    sleep 2
    
    # Force kill if still running
    if pgrep -f openvpn > /dev/null; then
        log "WARN" "Force killing OpenVPN processes"
        run_as_root pkill -9 -f openvpn || true
        sleep 1
    fi
}

# Restore original DNS configuration
restore_dns() {
    log "INFO" "Restoring original DNS configuration"
    
    # Restart systemd-resolved to restore original DNS
    run_as_root systemctl restart systemd-resolved 2>/dev/null || true
    
    # Remove any custom DNS entries we might have added
    if [[ -f /etc/systemd/resolved.conf.backup ]]; then
        run_as_root cp /etc/systemd/resolved.conf.backup /etc/systemd/resolved.conf
        run_as_root systemctl restart systemd-resolved
        run_as_root rm /etc/systemd/resolved.conf.backup
    fi
}

# Set VPN DNS servers
set_vpn_dns() {
    local dns_servers="$1"
    
    log "INFO" "Setting VPN DNS servers: $dns_servers"
    
    # Backup current resolved.conf if not already backed up
    if [[ ! -f /etc/systemd/resolved.conf.backup ]]; then
        run_as_root cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup
    fi
    
    # Configure systemd-resolved to use PIA DNS
    run_as_root tee /etc/systemd/resolved.conf > /dev/null << EOF
[Resolve]
DNS=${dns_servers//,/ }
FallbackDNS=
Domains=~.
DNSSEC=no
DNSOverTLS=no
EOF
    
    run_as_root systemctl restart systemd-resolved
}

# Cleanup function for script termination
cleanup_on_exit() {
    log "INFO" "Performing cleanup on script exit"
    restore_dns
    protect_ssh_routes "delete"
}

# Validate PIA credentials
validate_credentials() {
    if [[ -z "$PIA_USERNAME" ]] || [[ -z "$PIA_PASSWORD" ]]; then
        log "ERROR" "PIA credentials not configured in .env file"
        return 1
    fi
    
    if [[ "$PIA_USERNAME" == "your_username_here" ]] || [[ "$PIA_PASSWORD" == "your_password_here" ]]; then
        log "ERROR" "Please configure your actual PIA credentials in .env file"
        return 1
    fi
    
    return 0
}

# Check internet connectivity
check_connectivity() {
    local host="${1:-8.8.8.8}"
    if ping -c 1 -W 5 "$host" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Wait for internet connectivity
wait_for_connectivity() {
    local timeout="${1:-30}"
    local count=0
    
    log "INFO" "Waiting for internet connectivity..."
    
    while [[ $count -lt $timeout ]]; do
        if check_connectivity; then
            log "INFO" "Internet connectivity confirmed"
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    log "ERROR" "Internet connectivity timeout after ${timeout}s"
    return 1
}

# Get the default gateway interface (for route protection)
get_default_gateway_info() {
    local gateway_line=$(ip route | grep "^default")
    local gateway_ip=$(echo "$gateway_line" | awk '{print $3}')
    local gateway_dev=$(echo "$gateway_line" | awk '{print $5}')
    echo "$gateway_ip:$gateway_dev"
}

# Initialize common functions
init_common() {
    # Load environment
    if ! load_env; then
        exit 1
    fi
    
    # Validate credentials
    if ! validate_credentials; then
        exit 1
    fi
    
    # Set up signal handlers for cleanup
    trap cleanup_on_exit EXIT INT TERM
    
    log "INFO" "Common functions initialized"
}