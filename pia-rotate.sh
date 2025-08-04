#!/bin/bash

# PIA WireGuard VPN Rotate Script
# Rotates IP address by connecting to a different PIA server

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

# Function to show help
show_help() {
    cat << EOF
PIA WireGuard VPN Rotate Script

Usage: $0 [SERVER_NAME]

Rotate IP address by connecting to a different PIA server.
If no server is specified, selects a random server.

Arguments:
  SERVER_NAME    Specific server to rotate to (optional)
                 Available: us_west, us_east, uk, ca_toronto, etc.

Options:
  -h, --help     Show this help message

Examples:
  $0             # Rotate to random server
  $0 us_east     # Rotate to US East server
  $0 uk          # Rotate to UK server

Available servers: us_west, us_east, uk
EOF
}

# Parse command line arguments
TARGET_SERVER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option $1" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$TARGET_SERVER" ]]; then
                TARGET_SERVER="$1"
            else
                echo "ERROR: Multiple server names provided" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Define available servers (only confirmed working servers)
AVAILABLE_SERVERS=(
    "us_west"
    "us_east" 
    "uk"
)

# Function to get current VPN server from config
get_current_server() {
    local current_config="$PROJECT_DIR/configs/current-wireguard.conf"
    if [[ -f "$current_config" ]]; then
        source "$current_config"
        echo "$SERVER_ID"
    fi
}

# Function to check if VPN is connected
is_connected() {
    local interfaces=$(wg show interfaces 2>/dev/null || echo "")
    [[ -n "$interfaces" ]]
}

# Get current connection info
CURRENT_SERVER=""
CURRENT_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")

if is_connected; then
    CURRENT_SERVER=$(get_current_server)
    if [[ -n "$CURRENT_SERVER" ]]; then
        log "INFO" "Currently connected to $CURRENT_SERVER (IP: $CURRENT_IP)"
    else
        log "INFO" "VPN connected but server unknown (IP: $CURRENT_IP)"
    fi
else
    log "INFO" "No VPN connection found (IP: $CURRENT_IP)"
fi

# Determine target server
if [[ -n "$TARGET_SERVER" ]]; then
    # Check if target server is valid
    if [[ " ${AVAILABLE_SERVERS[@]} " =~ " ${TARGET_SERVER} " ]]; then
        NEW_SERVER="$TARGET_SERVER"
    else
        echo "ERROR: Invalid server '$TARGET_SERVER'"
        echo "Available servers: ${AVAILABLE_SERVERS[*]}"
        exit 1
    fi
else
    # Select random server different from current
    POSSIBLE_SERVERS=("${AVAILABLE_SERVERS[@]}")
    
    # Remove current server from options if connected
    if [[ -n "$CURRENT_SERVER" ]]; then
        POSSIBLE_SERVERS=($(printf '%s\n' "${POSSIBLE_SERVERS[@]}" | grep -v "^${CURRENT_SERVER}$"))
    fi
    
    if [[ ${#POSSIBLE_SERVERS[@]} -eq 0 ]]; then
        echo "ERROR: No alternative servers available"
        exit 1
    fi
    
    # Select random server
    random_index=$((RANDOM % ${#POSSIBLE_SERVERS[@]}))
    NEW_SERVER="${POSSIBLE_SERVERS[$random_index]}"
fi

# Check if it's the same as current server
if [[ "$NEW_SERVER" == "$CURRENT_SERVER" ]]; then
    echo "Already connected to $NEW_SERVER"
    echo "Current IP: $CURRENT_IP"
    exit 0
fi

log "INFO" "Target server: $NEW_SERVER"

# Perform rotation
echo "Rotating VPN connection to $NEW_SERVER..."

# Disconnect if currently connected
if is_connected; then
    log "INFO" "Disconnecting current VPN connection..."
    "$SCRIPT_DIR/pia-wg-disconnect.sh" >/dev/null 2>&1 || true
    sleep 2
fi

# Connect to new server
log "INFO" "Connecting to $NEW_SERVER..."
if "$SCRIPT_DIR/pia-wg-connect.sh" "$NEW_SERVER"; then
    # Wait for connection to stabilize
    sleep 3
    
    # Get new IP
    NEW_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || echo "unknown")
    
    echo "✅ Successfully rotated to $NEW_SERVER"
    if [[ "$CURRENT_IP" != "unknown" && "$NEW_IP" != "unknown" && "$CURRENT_IP" != "$NEW_IP" ]]; then
        log "INFO" "IP changed from $CURRENT_IP to $NEW_IP"
        echo "IP changed: $CURRENT_IP → $NEW_IP"
    else
        echo "New IP: $NEW_IP"
    fi
    
    log "INFO" "VPN rotation completed successfully"
    exit 0
else
    log "ERROR" "Failed to connect to $NEW_SERVER"
    echo "❌ Failed to rotate VPN connection"
    exit 1
fi