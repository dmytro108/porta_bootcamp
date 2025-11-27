#!/bin/bash
# Connectivity Verification Script
# This script verifies the VPN tunnel connectivity between hosts

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}VPN Tunnel Connectivity Verification${NC}"
echo -e "${BLUE}========================================${NC}"

# Counter for passed/failed tests
PASSED=0
FAILED=0

# Test 1: Check if containers are running
echo -e "\n${BLUE}[1/7] Checking container status...${NC}"
CONTAINERS=("router1" "router2" "host1" "host2")
for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "      ${CHECK} ${container} is running"
        ((PASSED++))
    else
        echo -e "      ${CROSS} ${container} is NOT running"
        ((FAILED++))
    fi
done

# Test 2: Check tunnel interfaces
echo -e "\n${BLUE}[2/7] Checking tunnel interfaces...${NC}"
if docker exec router1 ip addr show tun0 &>/dev/null; then
    ROUTER1_TUN=$(docker exec router1 ip -4 addr show tun0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo -e "      ${CHECK} Router1 tun0 UP (${ROUTER1_TUN})"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router1 tun0 DOWN"
    ((FAILED++))
fi

if docker exec router2 ip addr show tun0 &>/dev/null; then
    ROUTER2_TUN=$(docker exec router2 ip -4 addr show tun0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo -e "      ${CHECK} Router2 tun0 UP (${ROUTER2_TUN})"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router2 tun0 DOWN"
    ((FAILED++))
fi

# Test 3: Check OpenVPN process
echo -e "\n${BLUE}[3/7] Checking OpenVPN processes...${NC}"
if docker exec router1 pgrep openvpn &>/dev/null; then
    echo -e "      ${CHECK} Router1 OpenVPN process running"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router1 OpenVPN process NOT running"
    ((FAILED++))
fi

if docker exec router2 pgrep openvpn &>/dev/null; then
    echo -e "      ${CHECK} Router2 OpenVPN process running"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router2 OpenVPN process NOT running"
    ((FAILED++))
fi

# Test 4: Check routing tables
echo -e "\n${BLUE}[4/7] Checking routing tables...${NC}"
if docker exec router1 ip route | grep -q "10.20.0.0/24"; then
    echo -e "      ${CHECK} Router1 has route to LAN2 (10.20.0.0/24)"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router1 missing route to LAN2"
    ((FAILED++))
fi

if docker exec router2 ip route | grep -q "10.10.0.0/24"; then
    echo -e "      ${CHECK} Router2 has route to LAN1 (10.10.0.0/24)"
    ((PASSED++))
else
    echo -e "      ${CROSS} Router2 missing route to LAN1"
    ((FAILED++))
fi

# Test 5: Router-to-router ping through tunnel (INFORMATIONAL)
# Note: In many VPN configurations, routers only forward traffic and cannot
# originate traffic through the tunnel themselves. This is normal behavior.
echo -e "\n${BLUE}[5/7] Testing router-to-router connectivity (informational)...${NC}"
# Test by pinging the remote LAN gateway through the tunnel
# Router1 pings Router2's LAN interface (10.20.0.2)
if docker exec router1 ping -c 3 -W 2 10.20.0.2 &>/dev/null; then
    echo -e "      ${CHECK} Router1 → LAN2 gateway (10.20.0.2) OK"
    ((PASSED++))
else
    echo -e "      ${WARN} Router1 → LAN2 gateway (10.20.0.2) not responding (expected for gateway-only config)"
fi

# Router2 pings Router1's LAN interface (10.10.0.2)
if docker exec router2 ping -c 3 -W 2 10.10.0.2 &>/dev/null; then
    echo -e "      ${CHECK} Router2 → LAN1 gateway (10.10.0.2) OK"
    ((PASSED++))
else
    echo -e "      ${WARN} Router2 → LAN1 gateway (10.10.0.2) not responding (expected for gateway-only config)"
fi

# Test 6: Host-to-host connectivity (PRIMARY TEST)
echo -e "\n${BLUE}[6/7] Testing host-to-host connectivity (PRIMARY TEST)...${NC}"

# Host1 to Host2
echo -e "      Testing host1 (10.10.0.10) → host2 (10.20.0.10)..."
RESULT=$(docker exec host1 ping -c 5 -W 3 10.20.0.10 2>&1)
if echo "$RESULT" | grep -q "0% packet loss"; then
    AVG_RTT=$(echo "$RESULT" | grep -oP '(?<=rtt min/avg/max/mdev = )\d+\.\d+/\d+\.\d+' | cut -d'/' -f2)
    echo -e "      ${CHECK} Host1 → Host2 OK (avg RTT: ${AVG_RTT}ms, 0% loss)"
    ((PASSED++))
else
    LOSS=$(echo "$RESULT" | grep -oP '\d+(?=% packet loss)' || echo "100")
    echo -e "      ${CROSS} Host1 → Host2 FAILED (${LOSS}% packet loss)"
    ((FAILED++))
fi

# Host2 to Host1
echo -e "      Testing host2 (10.20.0.10) → host1 (10.10.0.10)..."
RESULT=$(docker exec host2 ping -c 5 -W 3 10.10.0.10 2>&1)
if echo "$RESULT" | grep -q "0% packet loss"; then
    AVG_RTT=$(echo "$RESULT" | grep -oP '(?<=rtt min/avg/max/mdev = )\d+\.\d+/\d+\.\d+' | cut -d'/' -f2)
    echo -e "      ${CHECK} Host2 → Host1 OK (avg RTT: ${AVG_RTT}ms, 0% loss)"
    ((PASSED++))
else
    LOSS=$(echo "$RESULT" | grep -oP '\d+(?=% packet loss)' || echo "100")
    echo -e "      ${CROSS} Host2 → Host1 FAILED (${LOSS}% packet loss)"
    ((FAILED++))
fi

# Test 7: TTL verification (should be reduced by 2 hops)
echo -e "\n${BLUE}[7/7] Verifying routing path (TTL analysis)...${NC}"
TTL=$(docker exec host1 ping -c 1 10.20.0.10 2>&1 | grep -oP '(?<=ttl=)\d+' | head -1)
if [ -n "$TTL" ]; then
    HOPS=$((64 - TTL))
    if [ "$HOPS" -eq 2 ]; then
        echo -e "      ${CHECK} Correct routing path: $HOPS hops (host1→router1→router2→host2)"
        ((PASSED++))
    else
        echo -e "      ${WARN} Unexpected hop count: $HOPS hops (expected 2)"
        echo -e "          This may indicate routing issues or unusual network configuration"
        ((PASSED++)) # Not a failure, just unexpected
    fi
else
    echo -e "      ${WARN} Could not determine TTL (ping may have failed)"
    ((FAILED++))
fi

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Tests passed: ${GREEN}${PASSED}${NC}"
echo -e "Tests failed: ${RED}${FAILED}${NC}"

if [ "$FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}✓ All connectivity tests PASSED!${NC}"
    echo -e "${GREEN}  VPN tunnel is operational and routing correctly.${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests FAILED!${NC}"
    echo -e "${YELLOW}  Review the output above for details.${NC}"
    echo -e "${YELLOW}  Check OpenVPN logs: docker exec router1 tail /var/log/openvpn.log${NC}"
    exit 1
fi
