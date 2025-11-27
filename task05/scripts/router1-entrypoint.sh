#!/bin/bash

#############################################################################
# Router1 Entrypoint Script - OpenVPN Server & Routing Configuration
# 
# This script:
# 1. Enables IP forwarding
# 2. Starts OpenVPN server
# 3. Waits for tunnel interface (tun0)
# 4. Loads routing configuration from /etc/network/routes.conf
# 5. Loads iptables rules from /etc/network/iptables.rules
# 6. Keeps container running and tails OpenVPN logs
#
# Configuration files (Infrastructure as Code):
#   - /etc/network/routes.conf     - Static routes
#   - /etc/network/iptables.rules  - Firewall rules
#############################################################################

set -e  # Exit on error

# Configuration paths
IPTABLES_RULES="/etc/network/iptables.rules"
ROUTES_CONF="/etc/network/routes.conf"

echo "========================================"
echo "Router1 Initialization Starting..."
echo "========================================"

# Step 1: Enable IP forwarding
echo "[1/6] Enabling IP forwarding..."
# IP forwarding is set via docker-compose.yml sysctls
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "      ✓ IP forwarding enabled"
else
    echo "      ⚠ IP forwarding not enabled, attempting to enable..."
    echo 1 > /proc/sys/net/ipv4/ip_forward || echo "      ✗ Failed to enable (not critical if set via docker)"
fi

# Step 2: Display network configuration
echo "[2/6] Network interfaces:"
ip addr show eth0 | grep "inet " | awk '{print "      LAN1 (eth0):   " $2}'
ip addr show eth1 | grep "inet " | awk '{print "      Public (eth1): " $2}'

# Step 3: Start OpenVPN server
echo "[3/6] Starting OpenVPN server..."
if [ ! -f /etc/openvpn/server.conf ]; then
    echo "      ✗ ERROR: /etc/openvpn/server.conf not found!"
    exit 1
fi
openvpn --config /etc/openvpn/server.conf --daemon
echo "      ✓ OpenVPN server started"

# Step 4: Wait for tunnel interface to come up
echo "[4/6] Waiting for tun0 interface..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if ip link show tun0 &>/dev/null; then
        sleep 2  # Give it a moment to fully initialize
        TUN_IP=$(ip addr show tun0 | grep "inet " | awk '{print $2}')
        echo "      ✓ tun0 interface UP: $TUN_IP"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "      ✗ ERROR: tun0 interface did not come up within ${TIMEOUT}s"
    echo "      OpenVPN logs:"
    tail -20 /var/log/openvpn.log
    exit 1
fi

# Step 5: Load routing configuration
echo "[5/6] Loading routing configuration..."

# Check if routes.conf exists
if [ ! -f "$ROUTES_CONF" ]; then
    echo "      ⚠ WARNING: $ROUTES_CONF not found, skipping custom routes"
else
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
            # Route might already exist (added by OpenVPN automatically)
            if ip route | grep -q "$(echo $line | awk '{print $1}')"; then
                echo "      ℹ Route already exists: $line"
            else
                echo "      ⚠ Failed to add route: $line"
            fi
        fi
    done < "$ROUTES_CONF"
    
    if [ $ROUTES_APPLIED -eq 0 ]; then
        echo "      ℹ No custom routes applied (may be handled by OpenVPN)"
    fi
fi

# Verify critical routes
if ip route | grep -q "10.20.0.0/24"; then
    echo "      ✓ Route to LAN2 (10.20.0.0/24) verified"
else
    echo "      ⚠ Route to LAN2 not found (waiting for client connection)"
fi

# Step 6: Load iptables configuration
echo "[6/6] Loading iptables configuration..."

# Check if iptables.rules exists
if [ ! -f "$IPTABLES_RULES" ]; then
    echo "      ✗ ERROR: $IPTABLES_RULES not found!"
    echo "      Cannot configure firewall rules"
    exit 1
fi

# Apply iptables rules from configuration file
if iptables-restore -n < "$IPTABLES_RULES"; then
    echo "      ✓ iptables rules loaded from $IPTABLES_RULES"
    
    # Display applied rules
    RULE_COUNT=$(iptables -L FORWARD -n | grep -c "ACCEPT" || echo "0")
    echo "      ✓ $RULE_COUNT forwarding rules active"
else
    echo "      ✗ ERROR: Failed to load iptables rules"
    exit 1
fi

# Display current routing table
echo ""
echo "Current routing table:"
ip route | grep -E "(10\.10\.|10\.20\.|10\.8\.)" | sed 's/^/      /'

echo ""
echo "========================================"
echo "Router1 Initialization Complete!"
echo "========================================"
echo "Monitoring OpenVPN logs..."
echo "----------------------------------------"

# Keep container running and tail logs
tail -f /var/log/openvpn.log
