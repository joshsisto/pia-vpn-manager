# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PIA VPN Manager is a WireGuard-based VPN management system for Private Internet Access (PIA) that preserves SSH and Tailscale connectivity during VPN operations. The system supports both OpenVPN and WireGuard protocols with advanced SSH protection features.

## Core Commands

### Essential VPN Operations
```bash
# WireGuard (Primary Protocol)
./pia-wg-connect.sh [server_name]    # Connect to VPN via WireGuard
./pia-wg-disconnect.sh               # Disconnect WireGuard VPN
./pia-wg-status.sh                   # Show WireGuard connection status

# OpenVPN (Legacy Support)
./pia-connect.sh [server_name]       # Connect via OpenVPN
./pia-disconnect.sh                  # Disconnect OpenVPN
./pia-status.sh                     # Show OpenVPN status

# Server Management
./pia-list-servers.sh [filter]       # List available servers
./pia-rotate.sh [server_name]        # Rotate to different server

# System Setup
sudo ./setup-sudoers.sh             # Configure passwordless sudo (required)
./install.sh                        # Full system installation
```

### Testing Commands
```bash
./test-system.sh                     # System readiness check
./test-wireguard-ready.sh           # WireGuard capability test
./test-connection.sh                # Basic connectivity test
./quick-test.sh                     # Quick system validation
```

## Architecture

### Core Libraries
- `lib/common.sh` - Shared functions for logging, SSH protection, DNS management, and network utilities
- `lib/servers.sh` - Server management, configuration generation, and connectivity testing

### Main Scripts
- `pia-wg-connect.sh` - WireGuard connection with PIA API authentication and config generation
- `pia-wg-disconnect.sh` - Clean WireGuard disconnection with route restoration
- `pia-wg-status.sh` - Real-time WireGuard status and network information
- `pia-connect.sh` - OpenVPN connection (legacy)
- `pia-disconnect.sh` - OpenVPN disconnection (legacy)

### SSH Protection System
The system implements advanced SSH/Tailscale protection through:
- `scripts/wg-pre-up.sh` - Pre-connection SSH route protection
- `scripts/wg-post-down.sh` - Post-disconnection route cleanup
- `scripts/route-up.sh` - OpenVPN route protection (legacy)
- `scripts/route-down.sh` - OpenVPN route cleanup (legacy)

### Configuration Management
- `configs/wireguard/` - Generated WireGuard configuration files
- `configs/openvpn/` - OpenVPN configurations and certificates
- `configs/pia-servers.conf` - Server definitions and metadata
- `configs/current-wireguard.conf` - Active connection tracking

## Key Architecture Patterns

### WireGuard Configuration Flow
1. Authenticate with PIA API using credentials from `.env`
2. Obtain authentication token and server metadata
3. Generate WireGuard configuration with PIA-provided keys
4. Apply SSH protection routes before connection
5. Establish WireGuard interface with proper DNS settings
6. Verify connection and log status

### SSH Protection Mechanism
- Detects active SSH connections and Tailscale interfaces
- Creates high-priority routing rules for SSH traffic
- Uses Tailscale subnet (100.64.0.0/10) exclusion from VPN tunnel
- Preserves gateway routes for active SSH sources
- Implements failsafe cleanup on disconnection

### Error Handling Strategy
- Comprehensive logging to `logs/pia-vpn.log`
- Cleanup handlers for script termination
- State validation before operations
- Network connectivity verification
- Credential validation and API error handling

## Configuration

### Environment Setup (.env)
Required configuration file with PIA credentials and system settings:
- `PIA_USERNAME` / `PIA_PASSWORD` - PIA account credentials
- `VPN_LOG_LEVEL` - Logging verbosity (debug, info, warn, error)
- `TAILSCALE_SUBNET` - Network range for SSH protection
- `PIA_DNS_SERVERS` - DNS servers for VPN connection

### Server Configuration
Servers are defined in `configs/pia-servers.conf` with format:
```
server_name|display_name|hostname|country|protocol_support
```

### Sudo Requirements
Scripts require passwordless sudo for network operations. Configure with:
```bash
sudo ./setup-sudoers.sh
```

## Development Patterns

### Function Organization
- Common utilities in `lib/common.sh` (logging, network, SSH protection)
- Server-specific logic in `lib/servers.sh` (validation, configuration)
- Protocol-specific implementations in main scripts

### Logging Standards
- Use `log()` function with levels: ERROR, WARN, INFO, DEBUG
- File logging to `VPN_LOG_FILE` with timestamps
- Console output respects `VPN_LOG_LEVEL` setting

### Error Handling
- Functions return non-zero exit codes on failure
- Use `set -euo pipefail` in scripts for strict error handling
- Implement cleanup functions for resource management
- Validate inputs before processing

### Testing Approach
- System capability tests before operations
- Network connectivity validation
- Configuration validation
- Integration tests for full workflows

## Security Considerations

- Credentials stored in `.env` with 600 permissions
- Configuration files secured in protected directories
- SSH connection preservation is critical for remote systems
- DNS leak prevention through proper DNS configuration
- Kill switch capability available but disabled by default