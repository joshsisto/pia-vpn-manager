# PIA VPN Manager

WireGuard-based VPN management system for Private Internet Access (PIA) with SSH/Tailscale protection.

## Prerequisites

- Ubuntu/Debian Linux system
- Active PIA account
- WireGuard tools: `sudo apt install wireguard wireguard-tools curl jq`

## Installation

1. **Clone repository:**
   ```bash
   git clone https://github.com/joshsisto/pia-vpn-manager.git
   cd pia-vpn-manager
   ```

2. **Configure credentials:**
   ```bash
   cp .env.template .env
   nano .env  # Add your PIA username and password
   ```

3. **Setup sudo permissions:**
   ```bash
   sudo ./setup-sudoers.sh
   ```

## Usage

### Connect to VPN
```bash
./pia-wg-connect.sh us_west    # Connect to specific server
./pia-wg-connect.sh            # Connect to default server
```

### Check Status
```bash
./pia-wg-status.sh             # Full status info
./pia-wg-status.sh --summary   # Quick summary
```

### Disconnect
```bash
./pia-wg-disconnect.sh         # Safely disconnect
```

### Server Management
```bash
./pia-list-servers.sh          # List all servers
./pia-list-servers.sh us       # Filter by country
./pia-rotate.sh                # Switch to random server
./pia-rotate.sh us_east        # Switch to specific server
```

## Configuration

Edit `.env` file:
```bash
PIA_USERNAME=p1234567
PIA_PASSWORD=your_password_here
PIA_DEFAULT_SERVER=us_west
VPN_LOG_LEVEL=info
```

Popular servers: `us_west`, `us_east`, `uk`, `de_berlin`, `nl`, `jp`, `au_sydney`

## SSH/Tailscale Protection

The system automatically preserves SSH and Tailscale connections during VPN operations:

- **Route Protection** - Creates persistent routes for SSH traffic
- **Split Tunneling** - Excludes Tailscale subnet (100.64.0.0/10) from VPN tunnel  
- **Automatic Detection** - Identifies active SSH and Tailscale connections
- **Failsafe Cleanup** - Restores routes on disconnect or failure

```
┌─────────────┐     Protected Route      ┌──────────────┐
│   Your PC   │ ◄──────────────────────► │  Tailscale   │
└─────────────┘         (Direct)          └──────────────┘
                                                 │
                                                 │ Always Direct
                                                 │
┌─────────────┐      VPN Tunnel          ┌──────────────┐
│   Server    │ ◄═══════════════════════ │     PIA      │
└─────────────┘    All Other Traffic      └──────────────┘
```

## Troubleshooting

**Authentication issues:**
```bash
cat .env | grep PIA_  # Verify credentials
```

**Permission errors:**
```bash
sudo ./setup-sudoers.sh  # Re-run sudo setup
```

**Connection issues:**
```bash
ip link show | grep pia-      # Check interface
wg show                       # Check WireGuard status
```

**Manual cleanup:**
```bash
sudo wg-quick down configs/wireguard/pia-*.conf
sudo systemctl restart systemd-resolved
```

**Debug logging:**
```bash
export VPN_LOG_LEVEL=debug
./pia-wg-connect.sh us_west
tail -f logs/pia-vpn.log
```

## Project Structure

```
pia-vpn-manager/
├── pia-wg-connect.sh        # Main connection script
├── pia-wg-disconnect.sh     # Disconnection script
├── pia-wg-status.sh         # Status checking script
├── pia-rotate.sh            # IP rotation script
├── pia-list-servers.sh      # Server listing script
├── setup-sudoers.sh         # Sudo configuration
├── .env.template            # Credentials template
├── lib/                     # Function libraries
├── scripts/                 # SSH protection scripts
├── configs/                 # Generated configs
└── logs/                    # Application logs
```

## License

Personal use only. Review PIA's terms of service for usage restrictions.