#!/bin/bash

# WireGuard Post-Down Script
# This script runs after WireGuard interface goes down
# It cleans up SSH protection routes

# Get the script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/lib/common.sh"
load_env

log "INFO" "WireGuard Post-Down: Cleaning up SSH protection routes"

# Remove SSH protection routes after WireGuard is down
protect_ssh_routes "delete"

log "INFO" "WireGuard Post-Down: Cleanup complete"