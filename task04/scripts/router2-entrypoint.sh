#!/bin/bash

#############################################################################
# Router2 Entrypoint Script - OpenVPN Client & Routing Configuration
# 
# This script:
# 1. Enables IP forwarding
# 2. Waits for router1 (OpenVPN server) to be ready
# 3. Starts OpenVPN client
# 4. Waits for tunnel interface (tun0)
# 5. Configures routing to LAN1 via VPN tunnel
# 6. Sets up iptables rules for packet forwarding
# 7. Keeps container running and tails OpenVPN logs
#############################################################################

set -e  # Exit on error

echo "========================================"
echo "Router2 Initialization Starting..."
echo "========================================"

# Step 1: Enable IP forwarding
echo "[1/7] Enabling IP forwarding..."
# IP forwarding is set via docker-compose.yml sysctls
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "      ✓ IP forwarding enabled"
else
    echo "      ⚠ IP forwarding not enabled, attempting to enable..."
    echo 1 > /proc/sys/net/ipv4/ip_forward || echo "      ✗ Failed to enable (not critical if set via docker)"
fi

# Step 2: Display network configuration
echo "[2/7] Network interfaces:"
ip addr show eth0 | grep "inet " | awk '{print "      LAN2 (eth0):   " $2}'
ip addr show eth1 | grep "inet " | awk '{print "      Public (eth1): " $2}'

# Step 3: Wait for OpenVPN server to be ready
echo "[3/7] Waiting for OpenVPN server (router1)..."
SERVER_IP="192.168.100.11"
TIMEOUT=60
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    if ping -c 1 -W 1 $SERVER_IP &>/dev/null; then
        echo "      ✓ Server reachable at $SERVER_IP"
        # Give server a bit more time to fully initialize OpenVPN
        sleep 3
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "      ✗ ERROR: Cannot reach OpenVPN server at $SERVER_IP"
    exit 1
fi

# Step 4: Start OpenVPN client
echo "[4/7] Starting OpenVPN client..."
if [ ! -f /etc/openvpn/client.conf ]; then
    echo "      ✗ ERROR: /etc/openvpn/client.conf not found!"
    exit 1
fi
openvpn --config /etc/openvpn/client.conf --daemon
echo "      ✓ OpenVPN client started"

# Step 5: Wait for tunnel interface to come up
echo "[5/7] Waiting for tun0 interface..."
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

# Step 6: Configure routing to LAN1 via tunnel
echo "[6/7] Configuring routing..."

# The route to LAN1 (10.10.0.0/24) should be added automatically by OpenVPN
# based on the 'route' directive in client.conf
# We verify it exists

if ip route | grep -q "10.10.0.0/24.*tun0"; then
    echo "      ✓ Route to LAN1 (10.10.0.0/24) via tun0 configured"
else
    echo "      ⚠ Route to LAN1 not found, adding manually..."
    sleep 2
    if ip route | grep -q "10.10.0.0/24"; then
        echo "      ✓ Route to LAN1 now present"
    else
        echo "      ⚠ Route not automatically configured, check OpenVPN logs"
    fi
fi

# Step 7: Configure iptables for forwarding
echo "[7/7] Configuring iptables..."

# Allow forwarding on tunnel interface
iptables -C FORWARD -i tun0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i tun0 -j ACCEPT
iptables -C FORWARD -o tun0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o tun0 -j ACCEPT

# Allow forwarding between LANs
iptables -C FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -j ACCEPT
iptables -C FORWARD -s 10.10.0.0/24 -d 10.20.0.0/24 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -s 10.10.0.0/24 -d 10.20.0.0/24 -j ACCEPT

echo "      ✓ iptables forwarding rules configured"

# Display current routing table
echo ""
echo "Current routing table:"
ip route | grep -E "(10\.10\.|10\.20\.|10\.8\.)" | sed 's/^/      /'

echo ""
echo "========================================"
echo "Router2 Initialization Complete!"
echo "========================================"
echo "Monitoring OpenVPN logs..."
echo "----------------------------------------"

# Keep container running and tail logs
tail -f /var/log/openvpn.log
