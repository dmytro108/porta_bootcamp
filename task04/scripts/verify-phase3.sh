#!/bin/bash
# Phase 3 Verification Script
# Tests Docker infrastructure setup

echo "========================================="
echo "  Phase 3 - Docker Infrastructure Tests"
echo "========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((pass_count++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((fail_count++))
}

test_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Test 1: Container Status
echo "Test 1: Container Status"
echo "-------------------------"
CONTAINERS=$(docker compose ps -q | wc -l)
if [ "$CONTAINERS" -eq 4 ]; then
    test_pass "All 4 containers are running"
else
    test_fail "Expected 4 containers, found $CONTAINERS"
fi
echo ""

# Test 2: Network Creation
echo "Test 2: Network Creation"
echo "------------------------"
if docker network inspect task04_lan1 &>/dev/null; then
    test_pass "LAN1 network exists"
else
    test_fail "LAN1 network not found"
fi

if docker network inspect task04_lan2 &>/dev/null; then
    test_pass "LAN2 network exists"
else
    test_fail "LAN2 network not found"
fi

if docker network inspect task04_public &>/dev/null; then
    test_pass "Public network exists"
else
    test_fail "Public network not found"
fi
echo ""

# Test 3: IP Address Configuration
echo "Test 3: IP Address Configuration"
echo "---------------------------------"

# Router1
ROUTER1_LAN=$(docker exec router1 ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$ROUTER1_LAN" == "10.10.0.2" ]; then
    test_pass "Router1 LAN IP: $ROUTER1_LAN"
else
    test_fail "Router1 LAN IP: $ROUTER1_LAN (expected 10.10.0.2)"
fi

ROUTER1_PUB=$(docker exec router1 ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$ROUTER1_PUB" == "192.168.100.11" ]; then
    test_pass "Router1 Public IP: $ROUTER1_PUB"
else
    test_fail "Router1 Public IP: $ROUTER1_PUB (expected 192.168.100.11)"
fi

# Router2
ROUTER2_LAN=$(docker exec router2 ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$ROUTER2_LAN" == "10.20.0.2" ]; then
    test_pass "Router2 LAN IP: $ROUTER2_LAN"
else
    test_fail "Router2 LAN IP: $ROUTER2_LAN (expected 10.20.0.2)"
fi

ROUTER2_PUB=$(docker exec router2 ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$ROUTER2_PUB" == "192.168.100.12" ]; then
    test_pass "Router2 Public IP: $ROUTER2_PUB"
else
    test_fail "Router2 Public IP: $ROUTER2_PUB (expected 192.168.100.12)"
fi

# Host1
HOST1_IP=$(docker exec host1 ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$HOST1_IP" == "10.10.0.10" ]; then
    test_pass "Host1 IP: $HOST1_IP"
else
    test_fail "Host1 IP: $HOST1_IP (expected 10.10.0.10)"
fi

# Host2
HOST2_IP=$(docker exec host2 ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
if [ "$HOST2_IP" == "10.20.0.10" ]; then
    test_pass "Host2 IP: $HOST2_IP"
else
    test_fail "Host2 IP: $HOST2_IP (expected 10.20.0.10)"
fi
echo ""

# Test 4: IP Forwarding
echo "Test 4: IP Forwarding"
echo "---------------------"
ROUTER1_FWD=$(docker exec router1 cat /proc/sys/net/ipv4/ip_forward)
if [ "$ROUTER1_FWD" == "1" ]; then
    test_pass "Router1 IP forwarding enabled"
else
    test_fail "Router1 IP forwarding disabled"
fi

ROUTER2_FWD=$(docker exec router2 cat /proc/sys/net/ipv4/ip_forward)
if [ "$ROUTER2_FWD" == "1" ]; then
    test_pass "Router2 IP forwarding enabled"
else
    test_fail "Router2 IP forwarding disabled"
fi
echo ""

# Test 5: LAN Connectivity
echo "Test 5: LAN Connectivity"
echo "------------------------"
if docker exec host1 ping -c 2 -W 2 10.10.0.2 &>/dev/null; then
    test_pass "Host1 can ping Router1"
else
    test_fail "Host1 cannot ping Router1"
fi

if docker exec host2 ping -c 2 -W 2 10.20.0.2 &>/dev/null; then
    test_pass "Host2 can ping Router2"
else
    test_fail "Host2 cannot ping Router2"
fi
echo ""

# Test 6: Router Connectivity (Public Network)
echo "Test 6: Router Connectivity (Public Network)"
echo "---------------------------------------------"
if docker exec router1 ping -c 2 -W 2 192.168.100.12 &>/dev/null; then
    test_pass "Router1 can ping Router2 (public network)"
else
    test_fail "Router1 cannot ping Router2 (public network)"
fi

if docker exec router2 ping -c 2 -W 2 192.168.100.11 &>/dev/null; then
    test_pass "Router2 can ping Router1 (public network)"
else
    test_fail "Router2 cannot ping Router1 (public network)"
fi
echo ""

# Test 7: Cross-LAN (Should Fail Without VPN)
echo "Test 7: Cross-LAN Connectivity (Expected to FAIL)"
echo "--------------------------------------------------"
if timeout 3 docker exec host1 ping -c 1 -W 2 10.20.0.10 &>/dev/null; then
    test_fail "Host1 can reach Host2 (unexpected - VPN not configured!)"
else
    test_pass "Host1 cannot reach Host2 (expected - VPN not configured)"
fi
echo ""

# Test 8: TUN Device Availability
echo "Test 8: TUN Device Availability"
echo "--------------------------------"
if docker exec router1 ls /dev/net/tun &>/dev/null; then
    test_pass "Router1 has /dev/net/tun access"
else
    test_fail "Router1 missing /dev/net/tun"
fi

if docker exec router2 ls /dev/net/tun &>/dev/null; then
    test_pass "Router2 has /dev/net/tun access"
else
    test_fail "Router2 missing /dev/net/tun"
fi
echo ""

# Test 9: PKI Files Mounted
echo "Test 9: PKI Files Mounted"
echo "-------------------------"
if docker exec router1 ls /etc/openvpn/ca.crt &>/dev/null; then
    test_pass "Router1 PKI files mounted"
else
    test_fail "Router1 PKI files not found"
fi

if docker exec router2 ls /etc/openvpn/ca.crt &>/dev/null; then
    test_pass "Router2 PKI files mounted"
else
    test_fail "Router2 PKI files not found"
fi
echo ""

# Summary
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ Phase 3 verification PASSED${NC}"
    echo "Ready to proceed to Phase 4 (OpenVPN Configuration)"
    exit 0
else
    echo -e "${RED}✗ Phase 3 verification FAILED${NC}"
    echo "Please fix the failing tests before proceeding"
    exit 1
fi
