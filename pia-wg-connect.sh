#!/bin/bash

# PIA WireGuard VPN Connection Script
# This script connects to Private Internet Access VPN using WireGuard protocol
# with SSH/Tailscale protection to preserve remote connectivity

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

# Setup cleanup on exit
trap cleanup_on_exit EXIT

log "INFO" "Common functions initialized"

# Check for required commands
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR" "Required command '$1' not found. Please install it."
        exit 1
    fi
}

check_command "wg"
check_command "wg-quick"
check_command "curl"
check_command "jq"

# Function to get PIA authentication token (internal - no logging)
_get_pia_token_raw() {
    local username="$1"
    local password="$2"
    
    # Use form data with proper headers to bypass Cloudflare
    local response=$(curl -s --location --request POST \
        'https://www.privateinternetaccess.com/api/client/v2/token' \
        --header 'User-Agent: Mozilla/5.0 (Linux; x86_64; rv:91.0) Gecko/20100101 Firefox/91.0' \
        --data-urlencode "username=$username" \
        --data-urlencode "password=$password")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if response is HTML (Cloudflare block)
    if echo "$response" | grep -q "<!DOCTYPE html>"; then
        return 1
    fi
    
    local token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
        return 1
    fi
    
    echo "$token"
}

# Function to get PIA authentication token (with logging)
get_pia_token() {
    local username="$1"
    local password="$2"
    
    log "INFO" "Obtaining PIA authentication token..."
    
    local token=$(_get_pia_token_raw "$username" "$password")
    
    if [[ $? -ne 0 ]] || [[ -z "$token" ]]; then
        log "ERROR" "Failed to obtain authentication token. Check credentials."
        return 1
    fi
    
    log "INFO" "Authentication token obtained successfully"
    echo "$token"
}

# Function to get PIA server information from server list API
get_server_info() {
    local server_id="$1"
    
    # Download current server list
    local serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v6'
    local server_data=$(curl -s "$serverlist_url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$server_data" ]]; then
        log "WARN" "Failed to fetch server list, using fallback data"
        # Fallback to known servers
        case "$server_id" in
            "us_west"|"us-west"|"us3")
                echo "us3.privacy.network|173.244.56.132"
                ;;
            "us_east"|"us-east"|"us_chicago")
                echo "us-chicago.privacy.network|173.244.63.155"
                ;;
            "uk")
                echo "uk.privacy.network|217.138.223.195"
                ;;
            *)
                log "ERROR" "Unknown server: $server_id"
                return 1
                ;;
        esac
        return 0
    fi
    
    # Map common server names to PIA server IDs
    local pia_server_id
    case "$server_id" in
        "us_west"|"us-west")
            pia_server_id="us3"
            ;;
        "us_east"|"us-east")
            pia_server_id="us_chicago"
            ;;
        "uk"|"united_kingdom")
            pia_server_id="uk"
            ;;
        *)
            pia_server_id="$server_id"
            ;;
    esac
    
    # Get server info from API response
    local hostname=$(echo "$server_data" | jq -r ".regions[] | select(.id == \"$pia_server_id\") | .dns" 2>/dev/null)
    local server_ip=$(echo "$server_data" | jq -r ".regions[] | select(.id == \"$pia_server_id\") | .servers.wg[0].ip" 2>/dev/null)
    
    if [[ -z "$hostname" ]] || [[ "$hostname" == "null" ]] || [[ -z "$server_ip" ]] || [[ "$server_ip" == "null" ]]; then
        log "ERROR" "Server '$server_id' not found in PIA server list"
        return 1
    fi
    
    echo "$hostname|$server_ip"
}

# Function to setup WireGuard connection
setup_wireguard() {
    local server_id="$1"
    local token="$2"
    
    log "INFO" "Setting up WireGuard connection to $server_id..." >&2
    
    # Get server information
    local server_info=$(get_server_info "$server_id" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local hostname=$(echo "$server_info" | cut -d'|' -f1)
    local server_ip=$(echo "$server_info" | cut -d'|' -f2)
    
    log "INFO" "Target server: $hostname ($server_ip)" >&2
    
    # Generate WireGuard keys
    umask 077
    local private_key=$(wg genkey)
    local public_key=$(echo "$private_key" | wg pubkey)
    
    # Call PIA WireGuard API to add our key
    log "INFO" "Registering WireGuard key with PIA..." >&2
    
    local api_response=$(curl -s -G \
        --connect-to "$hostname::$server_ip:" \
        --cacert "$PROJECT_DIR/configs/ca.rsa.4096.crt" \
        --data-urlencode "pt=$token" \
        --data-urlencode "pubkey=$public_key" \
        "https://$hostname:1337/addKey")
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to connect to PIA WireGuard API" >&2
        return 1
    fi
    
    # Parse API response
    local status=$(echo "$api_response" | jq -r '.status // empty')
    
    if [[ "$status" != "OK" ]]; then
        log "ERROR" "PIA API error: $(echo "$api_response" | jq -r '.message // "Unknown error"')" >&2
        return 1
    fi
    
    local peer_ip=$(echo "$api_response" | jq -r '.peer_ip // empty')
    local server_key=$(echo "$api_response" | jq -r '.server_key // empty')
    local server_port=$(echo "$api_response" | jq -r '.server_port // empty')
    local dns_servers=$(echo "$api_response" | jq -r '.dns_servers[]?' | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$peer_ip" || -z "$server_key" || -z "$server_port" ]]; then
        log "ERROR" "Invalid response from PIA WireGuard API" >&2
        return 1
    fi
    
    log "INFO" "WireGuard configuration received from PIA" >&2
    log "DEBUG" "Peer IP: $peer_ip" >&2
    log "DEBUG" "Server port: $server_port" >&2
    
    # Create WireGuard configuration directory
    local config_dir="$PROJECT_DIR/configs/wireguard"
    mkdir -p "$config_dir"
    
    # Create WireGuard configuration file
    local config_file="$config_dir/pia-$server_id.conf"
    
    cat > "$config_file" << EOF
[Interface]
PrivateKey = $private_key
Address = $peer_ip/32
DNS = ${dns_servers:-103.196.38.38,103.196.38.39}

# SSH Protection - Add routes for Tailscale traffic before connecting
PreUp = /home/josh/Sync2/projects/VPN2/pia-vpn-manager/scripts/wg-pre-up.sh
PostDown = /home/josh/Sync2/projects/VPN2/pia-vpn-manager/scripts/wg-post-down.sh

[Peer]
PublicKey = $server_key
Endpoint = $server_ip:$server_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Secure the configuration file
    chmod 600 "$config_file"
    
    log "INFO" "WireGuard configuration created: $config_file" >&2
    
    # Store connection info for other scripts
    cat > "$PROJECT_DIR/configs/current-wireguard.conf" << EOF
SERVER_ID=$server_id
CONFIG_FILE=$config_file
HOSTNAME=$hostname
SERVER_IP=$server_ip
PEER_IP=$peer_ip
EOF
    
    echo "$config_file"
}

# Function to connect using WireGuard
connect_wireguard() {
    local config_file="$1"
    local server_id="$2"
    
    log "INFO" "Establishing WireGuard connection..."
    
    # Check if already connected
    local interface_name=$(basename "$config_file" .conf)
    if ip link show "$interface_name" 2>/dev/null >/dev/null; then
        log "WARN" "WireGuard interface already exists. Disconnecting first..."
        run_as_root wg-quick down "$config_file" 2>/dev/null || true
        sleep 2
    fi
    
    # Connect using wg-quick
    if run_as_root wg-quick up "$config_file"; then
        log "INFO" "WireGuard connection established"
        
        # Wait a moment for the connection to stabilize
        sleep 3
        
        # Verify connection - check for the specific interface
        local interface_name=$(basename "$config_file" .conf)
        if ip link show "$interface_name" 2>/dev/null | grep -q "UP"; then
            log "INFO" "WireGuard interface is active"
            
            # Check if IP changed
            local new_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null)
            
            if [[ -n "$new_ip" && "$new_ip" != "209.38.155.4" ]]; then
                log "INFO" "✅ VPN connected successfully! New IP: $new_ip"
                echo "✅ Connected to $server_id via WireGuard"
                echo "New public IP: $new_ip"
                return 0
            else
                log "WARN" "WireGuard connected but IP may not have changed"
                echo "⚠️  WireGuard connected but IP verification inconclusive"
                return 0
            fi
        else
            log "ERROR" "WireGuard interface not found after connection attempt"
            return 1
        fi
    else
        log "ERROR" "Failed to establish WireGuard connection"
        return 1
    fi
}

# Main execution
main() {
    local server_id="${1:-$PIA_DEFAULT_SERVER}"
    
    if [[ -z "$server_id" ]]; then
        echo "Usage: $0 <server_id>"
        echo ""
        echo "Available servers:"
        echo "  us_west    - US West Coast"
        echo "  us_east    - US East Coast"
        echo "  uk         - United Kingdom"
        echo ""
        echo "Example: $0 us_west"
        exit 1
    fi
    
    log "INFO" "Starting WireGuard connection to $server_id"
    
    # Check current IP
    local current_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null)
    if [[ -n "$current_ip" ]]; then
        log "INFO" "Current public IP: $current_ip"
    fi
    
    # Get PIA token
    log "INFO" "Obtaining PIA authentication token..."
    local token=$(_get_pia_token_raw "$PIA_USERNAME" "$PIA_PASSWORD")
    if [[ $? -ne 0 ]] || [[ -z "$token" ]]; then
        log "ERROR" "Failed to authenticate with PIA"
        exit 1
    fi
    log "INFO" "Authentication token obtained successfully"
    
    # Setup SSH protection (this will be implemented in the next step)
    log "INFO" "Setting up SSH/Tailscale protection..."
    protect_ssh_routes "add"
    
    # Setup WireGuard configuration
    local config_file=$(setup_wireguard "$server_id" "$token")
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to setup WireGuard configuration"
        exit 1
    fi
    
    # Connect to VPN
    if connect_wireguard "$config_file" "$server_id"; then
        log "INFO" "WireGuard VPN connection successful"
        exit 0
    else
        log "ERROR" "WireGuard VPN connection failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi