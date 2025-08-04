# PIA VPN Manager

A robust WireGuard-based VPN management system for Private Internet Access (PIA) with SSH/Tailscale protection and IP rotation capabilities.

## 🎉 Features

- 🔒 **WireGuard Protocol** - Fast, modern VPN protocol with excellent performance
- 🛡️ **SSH Protection** - Preserves SSH and Tailscale connections during VPN operations
- 🔄 **IP Rotation** - Easy switching between different PIA servers worldwide
- 📊 **Status Monitoring** - Real-time connection status and network information
- 🚀 **Automatic Configuration** - Dynamic WireGuard config generation from PIA API
- 📝 **Comprehensive Logging** - Detailed logs for troubleshooting
- 🌍 **Global Server Support** - Access to all PIA server locations

## 📋 Prerequisites

- Ubuntu/Debian-based Linux system
- Active PIA account with credentials
- WireGuard tools installed
- curl, jq, and basic networking tools
- Tailscale (optional, for SSH protection features)

### Install Required Packages

```bash
sudo apt update
sudo apt install wireguard wireguard-tools curl jq
```

## 🚀 Installation

1. **Clone or download this repository:**
   ```bash
   git clone https://github.com/yourusername/pia-vpn-manager.git
   cd pia-vpn-manager
   ```

2. **Set up your PIA credentials:**
   ```bash
   cp .env.template .env
   nano .env  # Edit with your PIA username and password
   ```

3. **Configure sudo permissions (required for network operations):**
   ```bash
   sudo ./setup-sudoers.sh
   ```

4. **Make scripts executable:**
   ```bash
   chmod +x *.sh scripts/*.sh
   ```

## 📖 Usage

### Connect to VPN

Connect to a specific PIA server:
```bash
./pia-wg-connect.sh us_west
```

Example output:
```
INFO: Starting WireGuard connection to us_west
INFO: Current public IP: 209.38.155.4
INFO: Obtaining PIA authentication token...
INFO: Authentication token obtained successfully
INFO: Setting up SSH/Tailscale protection...
INFO: WireGuard connection established
INFO: ✅ VPN connected successfully! New IP: 173.244.56.62
✅ Connected to us_west via WireGuard
New public IP: 173.244.56.62
```

### Check VPN Status

View current connection status and network information:
```bash
./pia-wg-status.sh
```

Output includes:
- Active WireGuard connections
- Current public IP and location
- Transfer statistics
- SSH protection status

Quick summary:
```bash
./pia-wg-status.sh --summary
```

### Disconnect from VPN

Safely disconnect and restore original network settings:
```bash
./pia-wg-disconnect.sh
```

### List Available Servers

View all available PIA servers:
```bash
./pia-list-servers.sh          # Show all servers
./pia-list-servers.sh us       # Filter by country
./pia-list-servers.sh west     # Search by keyword
```

### Rotate IP Address

Switch to a different server:
```bash
./pia-rotate.sh                # Random server
./pia-rotate.sh us_east        # Specific server
```

## ⚙️ Configuration

### Environment Variables (.env)

```bash
# PIA Account Credentials (required)
PIA_USERNAME=p1234567
PIA_PASSWORD=your_password_here

# Default server (optional)
PIA_DEFAULT_SERVER=us_west

# Tailscale subnet for SSH protection
TAILSCALE_SUBNET=100.64.0.0/10

# Logging configuration
VPN_LOG_FILE=/home/josh/pia-vpn-manager/logs/pia-vpn.log
VPN_LOG_LEVEL=info  # Options: debug, info, warn, error
```

### Popular Server Locations

- `us_west` - US West Coast (Phoenix, Las Vegas, Los Angeles)
- `us_east` - US East Coast (New York, New Jersey, Washington DC)
- `us_chicago` - US Central (Chicago)
- `uk` - United Kingdom (London, Manchester)
- `ca_toronto` - Canada (Toronto)
- `de_berlin` - Germany (Berlin)
- `nl` - Netherlands (Amsterdam)
- `jp` - Japan (Tokyo)
- `au_sydney` - Australia (Sydney)

Use `./pia-list-servers.sh` to see all available locations.

## 🔐 SSH/Tailscale Protection

This system includes advanced route protection to preserve SSH connections during VPN operations:

1. **Automatic Detection** - Identifies active SSH and Tailscale connections
2. **Route Protection** - Creates persistent routes for SSH traffic
3. **Split Tunneling** - Excludes Tailscale subnet (100.64.0.0/10) from VPN tunnel
4. **Pre/Post Hooks** - Ensures protection before connection and cleanup after
5. **Failsafe Cleanup** - Restores routes on disconnect or failure

### How SSH Protection Works

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

## 🔧 Troubleshooting

### Common Issues and Solutions

#### "Login failed!" error
```bash
# Verify credentials
cat .env | grep PIA_

# Test authentication manually
source .env
curl -s --data-urlencode "username=$PIA_USERNAME" \
     --data-urlencode "password=$PIA_PASSWORD" \
     https://www.privateinternetaccess.com/api/client/v2/token
```

#### "Operation not permitted" errors
```bash
# Re-run sudo setup
sudo ./setup-sudoers.sh

# Verify sudo permissions
sudo -l | grep -E "(wg|ip)"
```

#### Connection succeeds but IP doesn't change
```bash
# Check WireGuard interface
ip link show | grep pia-
wg show

# Check routing
ip route | grep -E "(default|pia)"
```

#### SSH connection lost
```bash
# This shouldn't happen, but if it does:
# 1. Connect via console/physical access
# 2. Run: sudo ./pia-wg-disconnect.sh
# 3. Check Tailscale: tailscale status
```

### Debug Mode

Enable detailed logging:
```bash
export VPN_LOG_LEVEL=debug
./pia-wg-connect.sh us_west
```

View logs in real-time:
```bash
tail -f logs/pia-vpn.log
```

### Manual Cleanup

If a connection gets stuck:
```bash
# Force disconnect
sudo wg-quick down configs/wireguard/pia-us_west.conf

# Remove interface manually
sudo ip link delete pia-us_west 2>/dev/null

# Clean up DNS
sudo systemctl restart systemd-resolved
```

## 🚀 Advanced Usage

### Automatic Connection on Boot

Create a systemd service:

```bash
sudo nano /etc/systemd/system/pia-vpn.service
```

```ini
[Unit]
Description=PIA WireGuard VPN
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/home/josh/pia-vpn-manager/pia-wg-connect.sh us_west
ExecStop=/home/josh/pia-vpn-manager/pia-wg-disconnect.sh
Restart=on-failure
RestartSec=30
User=josh

[Install]
WantedBy=multi-user.target
```

Enable the service:
```bash
sudo systemctl enable pia-vpn
sudo systemctl start pia-vpn
```

### Scheduled IP Rotation

Add to crontab for automatic IP rotation:
```bash
# Rotate IP every 6 hours
0 */6 * * * /home/josh/pia-vpn-manager/pia-rotate.sh >> /home/josh/pia-vpn-manager/logs/rotation.log 2>&1
```

### Custom Scripts

Create custom automation using the libraries:

```bash
#!/bin/bash
# my-vpn-script.sh
source /home/josh/pia-vpn-manager/lib/common.sh
source /home/josh/pia-vpn-manager/lib/servers.sh

# Load environment
load_env

# Your custom logic here
if is_vpn_connected; then
    echo "VPN is connected"
    current_ip=$(curl -s ifconfig.me)
    echo "Current IP: $current_ip"
else
    echo "Connecting to VPN..."
    /home/josh/pia-vpn-manager/pia-wg-connect.sh us_west
fi
```

## 📁 Project Structure

```
pia-vpn-manager/
├── pia-wg-connect.sh        # Main connection script
├── pia-wg-disconnect.sh     # Disconnection script  
├── pia-wg-status.sh         # Status checking script
├── pia-rotate.sh            # IP rotation script
├── pia-list-servers.sh      # Server listing script
├── setup-sudoers.sh         # Sudo configuration
├── .env                     # Your credentials (create from template)
├── .env.template            # Template for credentials
├── lib/
│   ├── common.sh           # Common functions library
│   └── servers.sh          # Server management functions
├── scripts/
│   ├── wg-pre-up.sh        # Pre-connection SSH protection
│   ├── wg-post-down.sh     # Post-disconnection cleanup
│   ├── route-up.sh         # Legacy OpenVPN script (unused)
│   └── route-down.sh       # Legacy OpenVPN script (unused)
├── configs/
│   ├── wireguard/          # Generated WireGuard configs
│   ├── pia-servers.conf    # Server list cache
│   ├── ca.rsa.4096.crt     # PIA certificate
│   └── current-wireguard.conf  # Current connection info
└── logs/
    └── pia-vpn.log         # Application logs
```

## 🔒 Security Considerations

1. **Credentials** - Never commit `.env` file to version control
2. **Permissions** - Keep configuration files readable only by owner:
   ```bash
   chmod 600 .env
   chmod 600 configs/wireguard/*.conf
   ```
3. **Logging** - Logs may contain connection details (not passwords)
4. **DNS Leaks** - System uses PIA DNS servers (10.0.0.242/243) by default
5. **Kill Switch** - Not implemented; use firewall rules if needed:
   ```bash
   # Example kill switch
   sudo iptables -I OUTPUT ! -o pia-+ -m mark ! --mark $(wg show pia-us_west fwmark) -j DROP
   ```

## 📊 Performance Tips

- WireGuard is typically 3-4x faster than OpenVPN
- Use servers geographically close to you for best latency
- The `PersistentKeepalive` setting maintains NAT mappings
- MTU is set to 1420 to prevent fragmentation

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test thoroughly (especially SSH protection)
4. Update documentation
5. Submit a pull request

### Testing Checklist
- [ ] VPN connects successfully
- [ ] IP address changes
- [ ] SSH/Tailscale remains accessible
- [ ] Disconnect restores original state
- [ ] No DNS leaks
- [ ] Logs are informative

## 📜 License

This project is provided as-is for personal use. Please review PIA's terms of service for usage restrictions.

## 🙏 Acknowledgments

- Built using [PIA's official manual connection scripts](https://github.com/pia-foss/manual-connections) as reference
- WireGuard® is a registered trademark of Jason A. Donenfeld
- Special thanks to the Tailscale team for excellent documentation
- Thanks to the open-source community for tools and libraries

## 📞 Support

1. Check the logs: `tail -f logs/pia-vpn.log`
2. Run status check: `./pia-wg-status.sh`
3. Review troubleshooting section above
4. Check PIA's support documentation
5. Open an issue on GitHub with logs (remove sensitive data)

---

**Version:** 2.0.0 (WireGuard Edition)  
**Last Updated:** August 2025  
**Tested On:** Ubuntu 20.04/22.04 LTS