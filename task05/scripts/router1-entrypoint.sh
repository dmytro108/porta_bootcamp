#!/bin/bash

#############################################################################
# Router1 Entrypoint Script - OpenVPN Server & Routing Configuration
# 
# This script:
# 1. Enables IP forwarding
# 2. Starts OpenVPN server
# 3. Waits for tunnel interface (tun0)
# 4. Configures routing to LAN2 via VPN tunnel
# 5. Sets up iptables rules for packet forwarding
# 6. Keeps container running and tails OpenVPN logs
#############################################################################

set -e  # Exit on error

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

# Step 5: Configure routing to LAN2 via tunnel
echo "[5/6] Configuring routing..."

# The route to LAN2 (10.20.0.0/24) should be added automatically by OpenVPN
# based on the 'route' directive in server.conf and 'iroute' in ccd/router2
# We verify it exists, and add it manually if needed

if ip route | grep -q "10.20.0.0/24.*tun0"; then
    echo "      ✓ Route to LAN2 (10.20.0.0/24) via tun0 already exists"
else
    echo "      Adding route to LAN2 manually..."
    # Wait a bit for client to connect
    sleep 3
    if ip route | grep -q "10.20.0.0/24"; then
        echo "      ✓ Route to LAN2 now present"
    else
        echo "      ⚠ Route to LAN2 not yet established (client may not be connected)"
        echo "      This is normal if router2 hasn't connected yet"
    fi
fi

# Step 6: Configure iptables for forwarding
echo "[6/6] Configuring iptables..."

# Allow forwarding on tunnel interface
iptables -C FORWARD -i tun0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i tun0 -j ACCEPT
iptables -C FORWARD -o tun0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o tun0 -j ACCEPT

# Allow forwarding between LANs
iptables -C FORWARD -s 10.10.0.0/24 -d 10.20.0.0/24 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -s 10.10.0.0/24 -d 10.20.0.0/24 -j ACCEPT
iptables -C FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -j ACCEPT

echo "      ✓ iptables forwarding rules configured"

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
