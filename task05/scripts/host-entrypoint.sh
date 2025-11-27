#!/bin/bash

#############################################################################
# Host Entrypoint Script - Network Configuration
# 
# This script:
# 1. Loads routing configuration from /etc/network/routes.conf
# 2. Keeps container running
#
# Configuration files (Infrastructure as Code):
#   - /etc/network/routes.conf - Static routes
#############################################################################

set -e  # Exit on error

# Configuration paths
ROUTES_CONF="/etc/network/routes.conf"
HOSTNAME=$(hostname)

echo "========================================"
echo "$HOSTNAME Initialization Starting..."
echo "========================================"

# Step 1: Display network configuration
echo "[1/2] Network interfaces:"
ip addr show eth0 | grep "inet " | awk '{print "      eth0: " $2}'

# Step 2: Load routing configuration
echo "[2/2] Loading routing configuration..."

# Check if routes.conf exists
if [ ! -f "$ROUTES_CONF" ]; then
    echo "      ⚠ WARNING: $ROUTES_CONF not found, skipping route configuration"
else
    # Remove existing default route if any
    ip route del default 2>/dev/null || true
    
    # Parse and apply routes from configuration file
    ROUTES_APPLIED=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Apply the route
        if ip route add $line 2>/dev/null; then
            echo "      ✓ Added route: $line"
            ROUTES_APPLIED=$((ROUTES_APPLIED + 1))
        else
            # Route might already exist
            if ip route | grep -q "$(echo $line | awk '{print $1}')"; then
                echo "      ℹ Route already exists: $line"
            else
                echo "      ✗ Failed to add route: $line"
            fi
        fi
    done < "$ROUTES_CONF"
    
    if [ $ROUTES_APPLIED -eq 0 ]; then
        echo "      ⚠ No new routes applied"
    else
        echo "      ✓ Successfully applied $ROUTES_APPLIED route(s)"
    fi
fi

# Display current routing table
echo ""
echo "Current routing table:"
ip route | sed 's/^/      /'

echo ""
echo "========================================"
echo "$HOSTNAME Initialization Complete!"
echo "========================================"

# Keep container running
tail -f /dev/null
