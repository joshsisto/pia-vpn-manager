#!/bin/bash

# PIA WireGuard VPN Status Script
# This script displays the current status of WireGuard VPN connections
# including connection details, traffic statistics, and IP information

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

# Function to get current public IP
get_public_ip() {
    local ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo "Unable to determine"
    fi
}

# Function to get IP geolocation info
get_ip_location() {
    local ip="$1"
    if [[ -n "$ip" && "$ip" != "Unable to determine" ]]; then
        local info=$(curl -s --max-time 5 "http://ip-api.com/json/$ip" 2>/dev/null)
        if [[ -n "$info" ]]; then
            local country=$(echo "$info" | jq -r '.country // "Unknown"')
            local region=$(echo "$info" | jq -r '.regionName // "Unknown"')
            local city=$(echo "$info" | jq -r '.city // "Unknown"')
            local isp=$(echo "$info" | jq -r '.isp // "Unknown"')
            echo "$city, $region, $country ($isp)"
        else
            echo "Location lookup failed"
        fi
    else
        echo "N/A"
    fi
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [[ $bytes -gt 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

# Function to display WireGuard interface status
show_wireguard_status() {
    local interfaces=$(wg show interfaces 2>/dev/null)
    
    if [[ -z "$interfaces" ]]; then
        echo "❌ No active WireGuard connections"
        return 1
    fi
    
    echo "🔒 Active WireGuard connections:"
    echo
    
    for interface in $interfaces; do
        echo "Interface: $interface"
        
        # Get interface IP address
        local ip_addr=$(ip addr show "$interface" 2>/dev/null | grep "inet " | awk '{print $2}')
        if [[ -n "$ip_addr" ]]; then
            echo "  Interface IP: $ip_addr"
        fi
        
        # Get WireGuard details
        local wg_info=$(wg show "$interface" 2>/dev/null)
        
        if [[ -n "$wg_info" ]]; then
            # Extract peer information
            local peer_key=$(echo "$wg_info" | grep "peer:" | awk '{print $2}')
            local endpoint=$(echo "$wg_info" | grep "endpoint:" | awk '{print $2}')
            local allowed_ips=$(echo "$wg_info" | grep "allowed ips:" | cut -d':' -f2- | tr -d ' ')
            local latest_handshake=$(echo "$wg_info" | grep "latest handshake:" | cut -d':' -f2-)
            local transfer=$(echo "$wg_info" | grep "transfer:")
            
            if [[ -n "$peer_key" ]]; then
                echo "  Peer: ${peer_key:0:16}...${peer_key: -8}"
            fi
            
            if [[ -n "$endpoint" ]]; then
                echo "  Endpoint: $endpoint"
            fi
            
            if [[ -n "$allowed_ips" ]]; then
                echo "  Allowed IPs: $allowed_ips"
            fi
            
            if [[ -n "$latest_handshake" ]]; then
                echo "  Last handshake:$latest_handshake"
            fi
            
            if [[ -n "$transfer" ]]; then
                # Parse transfer data
                local received=$(echo "$transfer" | grep -o 'received,[^,]*' | cut -d',' -f2 | tr -d ' ')
                local sent=$(echo "$transfer" | grep -o 'sent,[^,]*' | cut -d',' -f2 | tr -d ' ')
                
                if [[ -n "$received" && -n "$sent" ]]; then
                    echo "  Transfer: ↓ $(format_bytes $received) / ↑ $(format_bytes $sent)"
                fi
            fi
        fi
        echo
    done
    
    return 0
}

# Function to display connection information
show_connection_info() {
    # Check for current connection info file
    local current_config="$PROJECT_DIR/configs/current-wireguard.conf"
    
    if [[ -f "$current_config" ]]; then
        source "$current_config"
        echo "📍 Connection Details:"
        echo "  Server ID: $SERVER_ID"
        echo "  Hostname: $HOSTNAME"
        echo "  Server IP: $SERVER_IP"
        if [[ -n "$PEER_IP" ]]; then
            echo "  VPN IP: $PEER_IP"
        fi
        echo
    fi
}

# Function to display network status
show_network_status() {
    echo "🌐 Network Status:"
    
    # Current public IP
    local current_ip=$(get_public_ip)
    echo "  Public IP: $current_ip"
    
    # Get location info
    if [[ "$current_ip" != "Unable to determine" ]]; then
        local location=$(get_ip_location "$current_ip")
        echo "  Location: $location"
    fi
    
    # Check if this looks like a VPN IP
    if [[ "$current_ip" != "209.38.155.4" && "$current_ip" != "Unable to determine" ]]; then
        echo "  Status: 🛡️  Protected (IP changed from original)"
    elif [[ "$current_ip" == "209.38.155.4" ]]; then
        echo "  Status: ⚠️  Not protected (original IP)"
    else
        echo "  Status: ❓ Unknown (cannot verify)"
    fi
    
    echo
}

# Function to display SSH protection status
show_ssh_status() {
    echo "🔐 SSH Protection Status:"
    
    # Check Tailscale interface
    local ts_interface=$(ip link show | grep "tailscale" | cut -d':' -f2 | tr -d ' ' | head -1)
    
    if [[ -n "$ts_interface" ]]; then
        local ts_ip=$(ip addr show "$ts_interface" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        echo "  Tailscale: ✅ Active ($ts_interface: $ts_ip)"
        
        # Check for SSH protection routes
        local ssh_rules=$(ip rule show | grep "100.64.0.0/10" | wc -l)
        if [[ $ssh_rules -gt 0 ]]; then
            echo "  SSH Routes: ✅ Protected ($ssh_rules rules active)"
        else
            echo "  SSH Routes: ⚠️  No protection rules found"
        fi
    else
        echo "  Tailscale: ❌ Not found"
        echo "  SSH Routes: ❓ Cannot verify without Tailscale"
    fi
    
    echo
}

# Function to display quick summary
show_summary() {
    local interfaces=$(wg show interfaces 2>/dev/null)
    local current_ip=$(get_public_ip)
    
    if [[ -n "$interfaces" ]]; then
        local interface_count=$(echo "$interfaces" | wc -w)
        echo "📊 Summary: ✅ $interface_count WireGuard connection(s) active"
    else
        echo "📊 Summary: ❌ No VPN connections active"
    fi
    
    echo "   Current IP: $current_ip"
    
    if [[ "$current_ip" != "209.38.155.4" && "$current_ip" != "Unable to determine" ]]; then
        echo "   Protection: 🛡️  VPN active"
    else
        echo "   Protection: ⚠️  No VPN protection"
    fi
}

# Function to display help
show_help() {
    echo "PIA WireGuard VPN Status"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -s, --summary  Show only summary information"
    echo "  -q, --quiet    Show minimal output"
    echo
    echo "Examples:"
    echo "  $0             Show full status"
    echo "  $0 --summary   Show summary only"
}

# Main execution
main() {
    local show_summary_only=false
    local quiet_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--summary)
                show_summary_only=true
                shift
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ "$quiet_mode" == true ]]; then
        # Quiet mode - just show connection status
        if wg show interfaces 2>/dev/null | head -1 | grep -q .; then
            echo "connected"
        else
            echo "disconnected"
        fi
        exit 0
    fi
    
    if [[ "$show_summary_only" == true ]]; then
        show_summary
        exit 0
    fi
    
    # Full status display
    echo "PIA WireGuard VPN Status"
    echo "========================"
    echo
    
    # Show WireGuard status
    if show_wireguard_status; then
        show_connection_info
    fi
    
    # Show network status
    show_network_status
    
    # Show SSH protection status
    show_ssh_status
    
    # Show summary
    show_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi