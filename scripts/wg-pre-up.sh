#!/bin/bash

# WireGuard Pre-Up Script
# This script runs before WireGuard interface comes up
# It protects SSH/Tailscale connections from being broken by VPN routing

# Get the script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/lib/common.sh"
load_env

log "INFO" "WireGuard Pre-Up: Protecting SSH/Tailscale routes"

# Protect SSH connections before WireGuard changes routing
protect_ssh_routes "add"

log "INFO" "WireGuard Pre-Up: SSH protection complete"