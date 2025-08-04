#!/bin/bash

# PIA VPN Manager - Server Management Functions
# This file contains functions for managing PIA server configurations

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVERS_CONFIG="$PROJECT_DIR/configs/pia-servers.conf"

# Load server information from config file
load_servers() {
    if [[ ! -f "$SERVERS_CONFIG" ]]; then
        log "ERROR" "Servers configuration file not found: $SERVERS_CONFIG"
        return 1
    fi
}

# Get all available server names
list_all_servers() {
    grep -v '^#' "$SERVERS_CONFIG" | grep -v '^$' | cut -d'|' -f1
}

# Get server info by name
get_server_info() {
    local server_name="$1"
    grep "^${server_name}|" "$SERVERS_CONFIG" 2>/dev/null
}

# Get server hostname by name
get_server_hostname() {
    local server_name="$1"
    local server_info=$(get_server_info "$server_name")
    if [[ -n "$server_info" ]]; then
        echo "$server_info" | cut -d'|' -f3
    else
        echo ""
    fi
}

# Get server display name by name
get_server_display_name() {
    local server_name="$1"
    local server_info=$(get_server_info "$server_name")
    if [[ -n "$server_info" ]]; then
        echo "$server_info" | cut -d'|' -f2
    else
        echo "$server_name"
    fi
}

# Get random server
get_random_server() {
    local servers=($(list_all_servers))
    local random_index=$((RANDOM % ${#servers[@]}))
    echo "${servers[$random_index]}"
}

# Search servers by pattern
search_servers() {
    local pattern="$1"
    grep -i "$pattern" "$SERVERS_CONFIG" | cut -d'|' -f1
}

# Validate server name
validate_server() {
    local server_name="$1"
    if [[ -z "$server_name" ]]; then
        return 1
    fi
    
    local server_info=$(get_server_info "$server_name")
    if [[ -n "$server_info" ]]; then
        return 0
    else
        return 1
    fi
}

# Download PIA certificates and keys (required for OpenVPN)
download_pia_certificates() {
    local cert_dir="$PROJECT_DIR/configs/openvpn"
    
    log "INFO" "Downloading PIA certificates..."
    
    # Create certificates directory
    mkdir -p "$cert_dir"
    
    # Download CA certificate
    if ! curl -fsSL -o "$cert_dir/ca.rsa.4096.crt" \
        "https://www.privateinternetaccess.com/openvpn/ca.rsa.4096.crt"; then
        log "ERROR" "Failed to download CA certificate"
        return 1
    fi
    
    # Download CRL
    if ! curl -fsSL -o "$cert_dir/crl.rsa.4096.pem" \
        "https://www.privateinternetaccess.com/openvpn/crl.rsa.4096.pem"; then
        log "ERROR" "Failed to download CRL"
        return 1
    fi
    
    log "INFO" "PIA certificates downloaded successfully"
    return 0
}

# Generate OpenVPN configuration for a server
generate_server_config() {
    local server_name="$1"
    local config_dir="$PROJECT_DIR/configs/openvpn"
    local template_file="$PROJECT_DIR/configs/pia-template.ovpn"
    local auth_file="$config_dir/auth.txt"
    local config_file="$config_dir/${server_name}.ovpn"
    local pia_original="$PROJECT_DIR/${server_name}.ovpn"
    
    # Validate server
    if ! validate_server "$server_name"; then
        log "ERROR" "Invalid server name: $server_name"
        return 1
    fi
    
    # Create auth file with credentials
    echo "$PIA_USERNAME" > "$auth_file"
    echo "$PIA_PASSWORD" >> "$auth_file"
    chmod 600 "$auth_file"
    
    # Use original PIA config if available, otherwise use template
    if [[ -f "$pia_original" ]]; then
        log "DEBUG" "Using original PIA config for $server_name"
        # Copy PIA config and modify it
        cp "$pia_original" "$config_file"
        
        # Ensure auth-user-pass points to our auth file
        sed -i "s|^auth-user-pass.*|auth-user-pass $auth_file|" "$config_file"
        
        # Add our SSH protection scripts if not already present
        if ! grep -q "route-up.sh" "$config_file"; then
            cat >> "$config_file" << EOF

# Route configuration to preserve SSH and handle DNS
script-security 2
route-noexec
up $PROJECT_DIR/scripts/route-up.sh
down $PROJECT_DIR/scripts/route-down.sh
EOF
        fi
    else
        log "DEBUG" "Using template for $server_name"
        # Get server hostname
        local hostname=$(get_server_hostname "$server_name")
        if [[ -z "$hostname" ]]; then
            log "ERROR" "Could not get hostname for server: $server_name"
            return 1
        fi
        
        # Generate config from template
        sed -e "s|SERVER_HOSTNAME|$hostname|g" \
            -e "s|AUTH_FILE|$auth_file|g" \
            -e "s|ROUTE_UP_SCRIPT|$PROJECT_DIR/scripts/route-up.sh|g" \
            -e "s|ROUTE_DOWN_SCRIPT|$PROJECT_DIR/scripts/route-down.sh|g" \
            "$template_file" > "$config_file"
    fi
    
    log "INFO" "Generated OpenVPN config for $server_name: $config_file"
    echo "$config_file"
}

# Clean up old server configurations
cleanup_old_configs() {
    local config_dir="$PROJECT_DIR/configs/openvpn"
    local keep_recent="${1:-5}"  # Keep last 5 configs by default
    
    # Remove configs older than recent ones, but keep auth.txt and certificates
    find "$config_dir" -name "*.ovpn" -type f -printf '%T@ %p\n' | \
        sort -rn | \
        tail -n +$((keep_recent + 1)) | \
        cut -d' ' -f2- | \
        xargs -r rm -f
    
    log "DEBUG" "Cleaned up old OpenVPN configurations (kept $keep_recent recent)"
}

# List servers by country/region
list_servers_by_country() {
    local country="$1"
    if [[ -n "$country" ]]; then
        grep -i "|$country|" "$SERVERS_CONFIG" | cut -d'|' -f1,2
    else
        # List all with country info
        grep -v '^#' "$SERVERS_CONFIG" | grep -v '^$' | cut -d'|' -f1,2,4
    fi
}

# Get server ping/latency (basic connectivity test)
test_server_connectivity() {
    local server_name="$1"
    local hostname=$(get_server_hostname "$server_name")
    
    if [[ -z "$hostname" ]]; then
        echo "ERROR: Invalid server"
        return 1
    fi
    
    # Test connectivity with timeout
    local ping_result=$(ping -c 3 -W 2 "$hostname" 2>/dev/null | grep "time=" | tail -1)
    if [[ -n "$ping_result" ]]; then
        echo "$ping_result" | grep -o "time=[0-9.]*" | cut -d'=' -f2
    else
        echo "TIMEOUT"
        return 1
    fi
}

# Find fastest servers (ping-based)
find_fastest_servers() {
    local count="${1:-5}"
    local temp_file=$(mktemp)
    
    log "INFO" "Testing server connectivity (this may take a moment)..."
    
    while IFS= read -r server; do
        local latency=$(test_server_connectivity "$server" 2>/dev/null)
        if [[ "$latency" != "TIMEOUT" ]] && [[ "$latency" =~ ^[0-9.]+$ ]]; then
            echo "$latency $server" >> "$temp_file"
        fi
    done < <(list_all_servers)
    
    # Sort by latency and return top results
    sort -n "$temp_file" | head -n "$count" | while read -r latency server; do
        local display_name=$(get_server_display_name "$server")
        echo "$server ($display_name) - ${latency}ms"
    done
    
    rm -f "$temp_file"
}