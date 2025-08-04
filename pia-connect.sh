#!/bin/bash

# PIA VPN Connect Script
# Connects to a specific PIA VPN server with SSH/Tailscale protection

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
PIA VPN Connect Script

Usage: $0 [OPTIONS] [SERVER_NAME]

Connect to a PIA VPN server with SSH/Tailscale protection.

Arguments:
  SERVER_NAME    Name of the PIA server to connect to
                 If not provided, uses PIA_DEFAULT_SERVER from .env
                 Use 'random' to connect to a random server

Options:
  -h, --help     Show this help message
  -l, --list     List available servers and exit
  -t, --test     Test connectivity to server before connecting
  -f, --force    Force connection (disconnect existing VPN first)
  -q, --quiet    Suppress informational output

Examples:
  $0 us_west                    # Connect to US West server
  $0 random                     # Connect to random server
  $0 --force uk_london          # Force connect to UK London
  $0 --test de_frankfurt        # Test Frankfurt server connectivity
  $0 --list                     # List all available servers

EOF
}

# Parse command line arguments
FORCE_CONNECT=false
TEST_ONLY=false
QUIET=false
SERVER_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            load_servers
            echo "Available PIA servers:"
            list_servers_by_country | while IFS='|' read -r name display country; do
                printf "  %-20s %-25s %s\n" "$name" "$display" "$country"
            done
            exit 0
            ;;
        -t|--test)
            TEST_ONLY=true
            shift
            ;;
        -f|--force)
            FORCE_CONNECT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -*)
            echo "ERROR: Unknown option $1" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$SERVER_NAME" ]]; then
                SERVER_NAME="$1"
            else
                echo "ERROR: Multiple server names provided" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Initialize common functions and validate environment
init_common
check_privileges

# Load server functions
load_servers

# Determine server to connect to
if [[ -z "$SERVER_NAME" ]]; then
    if [[ -n "$PIA_DEFAULT_SERVER" ]]; then
        SERVER_NAME="$PIA_DEFAULT_SERVER"
        [[ "$QUIET" != "true" ]] && log "INFO" "Using default server: $SERVER_NAME"
    else
        SERVER_NAME=$(get_random_server)
        [[ "$QUIET" != "true" ]] && log "INFO" "No server specified, using random: $SERVER_NAME"
    fi
elif [[ "$SERVER_NAME" == "random" ]]; then
    SERVER_NAME=$(get_random_server)
    [[ "$QUIET" != "true" ]] && log "INFO" "Selected random server: $SERVER_NAME"
fi

# Validate server name
if ! validate_server "$SERVER_NAME"; then
    log "ERROR" "Invalid server name: $SERVER_NAME"
    echo "Use --list to see available servers"
    exit 1
fi

# Get server info
SERVER_DISPLAY=$(get_server_display_name "$SERVER_NAME")
SERVER_HOSTNAME=$(get_server_hostname "$SERVER_NAME")

[[ "$QUIET" != "true" ]] && log "INFO" "Target server: $SERVER_DISPLAY ($SERVER_HOSTNAME)"

# Test connectivity if requested
if [[ "$TEST_ONLY" == "true" ]]; then
    log "INFO" "Testing connectivity to $SERVER_DISPLAY..."
    latency=$(test_server_connectivity "$SERVER_NAME")
    if [[ "$latency" != "TIMEOUT" ]]; then
        echo "✓ $SERVER_DISPLAY is reachable (${latency}ms)"
        exit 0
    else
        echo "✗ $SERVER_DISPLAY is not reachable"
        exit 1
    fi
fi

# Check if VPN is already connected
if is_vpn_connected; then
    current_server=$(get_current_vpn_server)
    if [[ "$current_server" == "$SERVER_NAME" ]]; then
        [[ "$QUIET" != "true" ]] && log "INFO" "Already connected to $SERVER_DISPLAY"
        exit 0
    elif [[ "$FORCE_CONNECT" == "true" ]]; then
        log "INFO" "Disconnecting from current VPN connection..."
        kill_openvpn
        sleep 2
    else
        log "ERROR" "VPN is already connected to $(get_server_display_name "$current_server")"
        echo "Use --force to disconnect and reconnect, or run pia-disconnect.sh first"
        exit 1
    fi
fi

# Check internet connectivity before connecting
if ! check_connectivity; then
    log "ERROR" "No internet connectivity detected"
    exit 1
fi

# Get current IP for comparison
ORIGINAL_IP=$(get_public_ip)
[[ "$QUIET" != "true" ]] && log "INFO" "Current public IP: $ORIGINAL_IP"

# Ensure certificates are available
if [[ ! -f "$PROJECT_DIR/configs/openvpn/ca.rsa.4096.crt" ]]; then
    log "INFO" "Downloading PIA certificates..."
    if ! download_pia_certificates; then
        log "ERROR" "Failed to download PIA certificates"
        exit 1
    fi
fi

# Generate OpenVPN configuration
log "INFO" "Generating OpenVPN configuration for $SERVER_DISPLAY..."
if generate_server_config "$SERVER_NAME" >/dev/null; then
    CONFIG_FILE="$PROJECT_DIR/configs/openvpn/${SERVER_NAME}.ovpn"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Failed to generate OpenVPN configuration file"
        exit 1
    fi
else
    log "ERROR" "Failed to generate OpenVPN configuration"
    exit 1
fi

# Pre-connection SSH route protection
log "INFO" "Setting up SSH/Tailscale protection..."
protect_ssh_routes "add"

# Create OpenVPN log file
OPENVPN_LOG="$OPENVPN_LOG_DIR/openvpn-${SERVER_NAME}.log"
mkdir -p "$(dirname "$OPENVPN_LOG")"

# Start OpenVPN connection
log "INFO" "Connecting to $SERVER_DISPLAY..."
[[ "$QUIET" != "true" ]] && echo "Connecting to $SERVER_DISPLAY... (this may take up to 30 seconds)"

# Start OpenVPN in background
run_as_root openvpn --config "$CONFIG_FILE" \
        --log "$OPENVPN_LOG" \
        --daemon \
        --writepid /var/run/openvpn-pia.pid

# Wait for connection to establish
log "INFO" "Waiting for VPN connection to establish..."
CONNECTION_ATTEMPTS=0
MAX_ATTEMPTS=$((CONNECTION_TIMEOUT))

while [[ $CONNECTION_ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
    if is_vpn_connected; then
        # Wait a bit more for routing to stabilize
        sleep 3
        
        # Verify we can still reach the internet
        if wait_for_connectivity 10; then
            NEW_IP=$(get_public_ip)
            
            if [[ "$NEW_IP" != "$ORIGINAL_IP" ]]; then
                [[ "$QUIET" != "true" ]] && echo "✓ Successfully connected to $SERVER_DISPLAY"
                log "INFO" "VPN connection established successfully"
                log "INFO" "IP changed from $ORIGINAL_IP to $NEW_IP"
                
                # Clean up old configurations
                cleanup_old_configs 10
                
                exit 0
            else
                log "WARN" "VPN connected but IP address didn't change"
            fi
        else
            log "ERROR" "VPN connected but no internet connectivity"
            break
        fi
    fi
    
    sleep 1
    ((CONNECTION_ATTEMPTS++))
    
    # Show progress
    if [[ "$QUIET" != "true" ]] && [[ $((CONNECTION_ATTEMPTS % 5)) -eq 0 ]]; then
        echo "Still connecting... (${CONNECTION_ATTEMPTS}s)"
    fi
done

# Connection failed
log "ERROR" "Failed to establish VPN connection within ${CONNECTION_TIMEOUT}s"

# Cleanup on failure
log "INFO" "Cleaning up failed connection attempt..."
kill_openvpn
protect_ssh_routes "delete"
restore_dns

# Show OpenVPN log for debugging
if [[ -f "$OPENVPN_LOG" ]]; then
    echo "OpenVPN log (last 10 lines):"
    tail -10 "$OPENVPN_LOG"
fi

exit 1