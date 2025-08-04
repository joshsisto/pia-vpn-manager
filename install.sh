#!/bin/bash

# PIA VPN Manager Installation Script
# Sets up the PIA VPN management system on Ubuntu Server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Help function
show_help() {
    cat << EOF
PIA VPN Manager Installation Script

Usage: $0 [OPTIONS]

Install and configure PIA VPN Manager on Ubuntu Server with SSH/Tailscale protection.

Options:
  -h, --help          Show this help message
  -y, --yes           Skip confirmation prompts (auto-yes)
  -u, --update        Update existing installation
  --skip-deps         Skip dependency installation
  --skip-certs        Skip certificate download
  --credentials USER:PASS  Set PIA credentials during install

Examples:
  $0                           # Interactive installation
  $0 --yes                     # Automatic installation  
  $0 --update                  # Update existing installation
  $0 --credentials user:pass   # Set credentials during install

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
AUTO_YES=false
UPDATE_MODE=false
SKIP_DEPS=false
SKIP_CERTS=false
PIA_CREDENTIALS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -u|--update)
            UPDATE_MODE=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-certs)
            SKIP_CERTS=true
            shift
            ;;
        --credentials)
            if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[^:]+:[^:]+$ ]]; then
                PIA_CREDENTIALS="$2"
                shift 2
            else
                log_error "--credentials requires format user:password"
                exit 1
            fi
            ;;
        -*)
            log_error "Unknown option $1"
            show_help
            exit 1
            ;;
        *)
            log_error "No arguments expected"
            show_help
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This installation script should NOT be run as root"
    log_info "Run as regular user - it will use sudo when needed"
    exit 1
fi

# Check if sudo is available
if ! command -v sudo >/dev/null 2>&1; then
    log_error "sudo is required but not installed"
    exit 1
fi

# Check OS compatibility
if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot determine OS version"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    log_warn "This script is designed for Ubuntu. Your OS: $ID"
    if [[ "$AUTO_YES" != "true" ]]; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Banner
echo -e "${BLUE}"
cat << 'EOF'
 ____  ___    _       __     ____  _   _   __  __                                   
|  _ \|_ _|  / \      \ \   / /  _ \| \ | | |  \/  | __ _ _ __   __ _  __ _  ___ _ __ 
| |_) || |  / _ \      \ \ / /| |_) |  \| | | |\/| |/ _` | '_ \ / _` |/ _` |/ _ \ '__|
|  __/ | | / ___ \      \ V / |  __/| |\  | | |  | | (_| | | | | (_| | (_| |  __/ |   
|_|   |___/_/   \_\      \_/  |_|   |_| \_| |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_|   
                                                                      |___/          
EOF
echo -e "${NC}"

echo "PIA VPN Manager Installation Script"
echo "===================================="
echo ""

# Show installation info
log_info "Installation directory: $PROJECT_DIR"
log_info "Current user: $(whoami)"
log_info "OS: $PRETTY_NAME"

# Check for existing installation
if [[ -f "$PROJECT_DIR/.env" ]] && [[ "$UPDATE_MODE" != "true" ]]; then
    log_warn "Existing installation detected"
    if [[ "$AUTO_YES" != "true" ]]; then
        read -p "Update existing installation? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 0
        fi
    fi
    UPDATE_MODE=true
fi

if [[ "$UPDATE_MODE" == "true" ]]; then
    log_info "Running in update mode"
fi

# Confirmation
if [[ "$AUTO_YES" != "true" ]]; then
    echo ""
    read -p "Continue with installation? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
fi

echo ""
log_info "Starting installation..."

# 1. Install dependencies
if [[ "$SKIP_DEPS" != "true" ]]; then
    log_info "Installing system dependencies..."
    
    # Update package list
    sudo apt-get update -qq
    
    # Install required packages
    PACKAGES=(
        "openvpn"
        "curl"
        "wget" 
        "dnsutils"
        "net-tools"
        "iproute2"
        "iptables"
        "resolvconf"
        "systemd-resolved"
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            sudo apt-get install -y "$package"
        else
            log_info "$package is already installed"
        fi
    done
    
    log_success "Dependencies installed"
else
    log_info "Skipping dependency installation"
fi

# 2. Create directories and set permissions
log_info "Setting up directory structure..."

mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/configs/openvpn"

# Ensure proper permissions
chmod 755 "$PROJECT_DIR"
chmod 755 "$PROJECT_DIR/scripts"
chmod 755 "$PROJECT_DIR/lib"
chmod 755 "$PROJECT_DIR/configs"
chmod 700 "$PROJECT_DIR/configs/openvpn"  # Secure config directory
chmod 700 "$PROJECT_DIR/logs"

log_success "Directory structure created"

# 3. Download PIA certificates
if [[ "$SKIP_CERTS" != "true" ]]; then
    log_info "Downloading PIA certificates..."
    
    CERT_DIR="$PROJECT_DIR/configs/openvpn"
    
    # Download CA certificate
    if ! curl -fsSL -o "$CERT_DIR/ca.rsa.4096.crt" \
        "https://www.privateinternetaccess.com/openvpn/ca.rsa.4096.crt"; then
        log_error "Failed to download CA certificate"
        exit 1
    fi
    
    # Download CRL
    if ! curl -fsSL -o "$CERT_DIR/crl.rsa.4096.pem" \
        "https://www.privateinternetaccess.com/openvpn/crl.rsa.4096.pem"; then
        log_error "Failed to download CRL"
        exit 1
    fi
    
    chmod 644 "$CERT_DIR/ca.rsa.4096.crt"
    chmod 644 "$CERT_DIR/crl.rsa.4096.pem"
    
    log_success "PIA certificates downloaded"
else
    log_info "Skipping certificate download"
fi

# 4. Configure environment file
log_info "Configuring environment..."

if [[ ! -f "$PROJECT_DIR/.env" ]] || [[ "$UPDATE_MODE" == "true" ]]; then
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        # Backup existing config
        cp "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing configuration"
    fi
    
    # Copy template
    cp "$PROJECT_DIR/.env.template" "$PROJECT_DIR/.env"
    
    # Set credentials if provided
    if [[ -n "$PIA_CREDENTIALS" ]]; then
        IFS=':' read -r username password <<< "$PIA_CREDENTIALS"
        sed -i "s|PIA_USERNAME=.*|PIA_USERNAME=$username|" "$PROJECT_DIR/.env"
        sed -i "s|PIA_PASSWORD=.*|PIA_PASSWORD=$password|" "$PROJECT_DIR/.env"
        log_success "PIA credentials configured"
    fi
    
    # Set proper permissions
    chmod 600 "$PROJECT_DIR/.env"
    
    log_success "Environment file configured"
fi

# 5. Make scripts executable
log_info "Setting script permissions..."

chmod +x "$PROJECT_DIR"/*.sh
chmod +x "$PROJECT_DIR/lib"/*.sh
chmod +x "$PROJECT_DIR/scripts"/*.sh

log_success "Script permissions set"

# 6. Create symlinks for easy access
log_info "Creating command symlinks..."

SYMLINK_DIR="/usr/local/bin"
SCRIPTS=(
    "pia-connect.sh:pia-connect"
    "pia-disconnect.sh:pia-disconnect"
    "pia-status.sh:pia-status"
    "pia-rotate.sh:pia-rotate"
    "pia-list-servers.sh:pia-list-servers"
)

for script_link in "${SCRIPTS[@]}"; do
    IFS=':' read -r script_name link_name <<< "$script_link"
    
    if [[ -L "$SYMLINK_DIR/$link_name" ]]; then
        sudo rm "$SYMLINK_DIR/$link_name"
    fi
    
    sudo ln -sf "$PROJECT_DIR/$script_name" "$SYMLINK_DIR/$link_name"
    log_info "Created symlink: $link_name -> $script_name"
done

log_success "Command symlinks created"

# 7. Verify Tailscale installation
log_info "Checking Tailscale configuration..."

if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_STATUS=$(tailscale status 2>/dev/null || echo "not running")
    if [[ "$TAILSCALE_STATUS" == "not running" ]]; then
        log_warn "Tailscale is installed but not running"
        log_info "Start Tailscale with: sudo tailscale up"
    else
        log_success "Tailscale is running"
    fi
else
    log_warn "Tailscale not found - SSH protection may be limited"
    log_info "Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh"
fi

# 8. Test installation
log_info "Testing installation..."

# Test basic script functionality
if [[ -f "$PROJECT_DIR/pia-status.sh" ]]; then
    if "$PROJECT_DIR/pia-status.sh" --help >/dev/null 2>&1; then
        log_success "Scripts are working correctly"
    else
        log_error "Script test failed"
        exit 1
    fi
else
    log_error "Scripts not found"
    exit 1
fi

# Test server list
if [[ -f "$PROJECT_DIR/pia-list-servers.sh" ]]; then
    server_count=$("$PROJECT_DIR/pia-list-servers.sh" --names | wc -l)
    if [[ $server_count -gt 0 ]]; then
        log_success "Server list loaded successfully ($server_count servers)"
    else
        log_error "No servers found in configuration"
        exit 1
    fi
fi

# 9. Final configuration
log_info "Finalizing installation..."

# Create log file
touch "$PROJECT_DIR/logs/pia-vpn.log"
chmod 644 "$PROJECT_DIR/logs/pia-vpn.log"

# Installation complete
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Show usage information
echo "Available Commands:"
echo "  pia-connect [server]     - Connect to VPN server"
echo "  pia-disconnect          - Disconnect from VPN"
echo "  pia-status              - Show VPN status"
echo "  pia-rotate              - Rotate to different server"
echo "  pia-list-servers        - List available servers"
echo ""

echo "Configuration:"
echo "  Config file: $PROJECT_DIR/.env"
echo "  Log file: $PROJECT_DIR/logs/pia-vpn.log"
echo ""

# Show next steps
if [[ -z "$PIA_CREDENTIALS" ]]; then
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Edit $PROJECT_DIR/.env and add your PIA credentials"
    echo "2. Test connection: sudo pia-connect us_west"
    echo "3. Check status: pia-status"
    echo ""
fi

echo -e "${GREEN}Important Security Notes:${NC}"
echo "• All VPN operations preserve SSH/Tailscale connectivity"
echo "• Scripts must be run with sudo for network configuration"
echo "• Credentials are stored securely in .env file (600 permissions)"
echo ""

# Show current network status
echo "Current Network Status:"
if command -v tailscale >/dev/null 2>&1; then
    echo "• Tailscale IP: $(tailscale ip 2>/dev/null || echo 'Not available')"
fi
echo "• Public IP: $(curl -s --connect-timeout 5 ipinfo.io/ip || echo 'Not available')"
echo ""

log_success "PIA VPN Manager is ready to use!"

exit 0