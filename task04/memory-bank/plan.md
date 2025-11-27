# VPN Tunnel Implementation Task Plan

## Project Overview

Implement a site-to-site OpenVPN tunnel between two LANs using Docker containers to emulate the entire network topology.

**Network Topology:**
- LAN1: 10.10.0.0/24 (host1: 10.10.0.10, router1: 10.10.0.1)
- LAN2: 10.20.0.0/24 (host2: 10.20.0.10, router2: 10.20.0.1)
- Public Network: 172.18.0.0/24 (router1: 172.18.0.11, router2: 172.18.0.12)
- VPN Tunnel: TUN interface (Layer 3)

**Success Criteria:**
- Successful ping from host1 (10.10.0.10) to host2 (10.20.0.10)
- Traffic encryption verification

---

## Phase 1: Environment Preparation

### Task 1.1: Project Structure Setup
**Duration:** 15 minutes

Create the following directory structure:
```
vpn-tunnel-lab/
├── docker-compose.yml
├── Dockerfile.router
├── Dockerfile.host
├── configs/
│   ├── router1/
│   │   ├── openvpn/
│   │   └── network/
│   └── router2/
│       ├── openvpn/
│       └── network/
├── pki/
│   ├── ca/
│   ├── certs/
│   └── keys/
└── scripts/
    ├── setup-pki.sh
    ├── verify-connectivity.sh
    └── verify-encryption.sh
```

**Actions:**
- Create base directory structure
- Initialize git repository (optional)
- Create README.md with project description

---

## Phase 2: PKI (Public Key Infrastructure) Setup

### Task 2.1: Install Easy-RSA
**Duration:** 10 minutes

**Actions:**
- Download Easy-RSA 3.x
- Extract to `pki/` directory
- Initialize PKI environment

**Commands:**
```bash
cd pki/
wget https://github.com/OpenVPN/easy-rsa/releases/latest/download/EasyRSA-3.x.x.tgz
tar xzf EasyRSA-3.x.x.tgz
cd EasyRSA-3.x.x/
./easyrsa init-pki
```

### Task 2.2: Create Certificate Authority (CA)
**Duration:** 15 minutes

**Actions:**
- Build CA certificate
- Set appropriate CN (Common Name)
- Secure ca.key with proper permissions

**Commands:**
```bash
./easyrsa build-ca nopass
# Enter CA name: "VPN-Lab-CA"
```

**Output files:**
- `pki/ca.crt` (CA certificate)
- `pki/private/ca.key` (CA private key)

### Task 2.3: Generate Server Certificates
**Duration:** 20 minutes

**Actions:**
- Generate certificate for router1 (OpenVPN server)
- Generate certificate for router2 (OpenVPN client)
- Sign certificates with CA

**Commands:**
```bash
# Router1 (Server)
./easyrsa build-server-full router1 nopass

# Router2 (Client)
./easyrsa build-client-full router2 nopass
```

**Output files:**
- `pki/issued/router1.crt`
- `pki/private/router1.key`
- `pki/issued/router2.crt`
- `pki/private/router2.key`

### Task 2.4: Generate Diffie-Hellman Parameters
**Duration:** 5-30 minutes (depending on system)

**Actions:**
- Generate DH parameters for key exchange
- Generate TLS-auth key for additional security

**Commands:**
```bash
./easyrsa gen-dh
openvpn --genkey secret ta.key
```

**Output files:**
- `pki/dh.pem`
- `ta.key`

### Task 2.5: Organize PKI Files
**Duration:** 10 minutes

**Actions:**
- Copy certificates and keys to appropriate router config directories
- Set proper file permissions (600 for keys, 644 for certs)

**File distribution:**

Router1 needs:
- `ca.crt`
- `router1.crt`
- `router1.key`
- `dh.pem`
- `ta.key`

Router2 needs:
- `ca.crt`
- `router2.crt`
- `router2.key`
- `ta.key`

---

## Phase 3: Docker Infrastructure

### Task 3.1: Create Docker Networks
**Duration:** 10 minutes

**Actions:**
- Define three custom bridge networks in docker-compose.yml
- Configure subnet and gateway for each network

**Network definitions:**
```yaml
networks:
  lan1:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.0.0/24
          gateway: 10.10.0.1
  
  lan2:
    driver: bridge
    ipam:
      config:
        - subnet: 10.20.0.0/24
          gateway: 10.20.0.1
  
  public:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/24
```

### Task 3.2: Create Router Dockerfile
**Duration:** 30 minutes

**Actions:**
- Base image: Alpine Linux or Ubuntu
- Install required packages:
  - OpenVPN
  - iptables
  - iproute2
  - tcpdump (for traffic analysis)
  - net-tools
- Enable IP forwarding
- Configure capabilities for VPN and routing

**Dockerfile.router:**
```dockerfile
FROM alpine:latest

RUN apk add --no-cache \
    openvpn \
    iptables \
    iproute2 \
    tcpdump \
    bash \
    net-tools \
    bind-tools

# Enable IP forwarding
RUN echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

CMD ["/bin/bash"]
```

**Required capabilities:**
- NET_ADMIN
- NET_RAW
- SYS_MODULE (for tun/tap)

### Task 3.3: Create Host Dockerfile
**Duration:** 15 minutes

**Actions:**
- Base image: Alpine Linux or Ubuntu
- Install basic networking tools
- Configure for testing

**Dockerfile.host:**
```dockerfile
FROM alpine:latest

RUN apk add --no-cache \
    iputils \
    bash \
    net-tools \
    bind-tools \
    tcpdump

CMD ["/bin/bash", "-c", "tail -f /dev/null"]
```

### Task 3.4: Create docker-compose.yml
**Duration:** 45 minutes

**Actions:**
- Define all 4 containers (router1, router2, host1, host2)
- Configure network attachments
- Set static IP addresses
- Mount PKI files and config directories
- Add necessary capabilities and devices

**Key configuration points:**

**Router1 (OpenVPN Server):**
- Networks: lan1 (10.10.0.1), public (172.18.0.11)
- Volumes: PKI files, OpenVPN server config
- Capabilities: NET_ADMIN, NET_RAW
- Devices: /dev/net/tun
- Privileged: true (or specific capabilities)

**Router2 (OpenVPN Client):**
- Networks: lan2 (10.20.0.1), public (172.18.0.12)
- Volumes: PKI files, OpenVPN client config
- Capabilities: NET_ADMIN, NET_RAW
- Devices: /dev/net/tun
- Privileged: true (or specific capabilities)

**Host1:**
- Networks: lan1 (10.10.0.10)
- Default gateway: 10.10.0.1

**Host2:**
- Networks: lan2 (10.20.0.10)
- Default gateway: 10.20.0.1

---

## Phase 4: OpenVPN Configuration

### Task 4.1: Configure OpenVPN Server (Router1)
**Duration:** 30 minutes

**Actions:**
- Create server configuration file
- Configure tunnel interface and addressing
- Set routing for LAN2 subnet
- Enable compression and encryption

**File:** `configs/router1/openvpn/server.conf`

**Key configuration parameters:**
```conf
# Network settings
dev tun0
dev-type tun
topology subnet

# Server mode
mode server
tls-server

# Tunnel network (VPN internal addressing)
ifconfig 10.8.0.1 10.8.0.2

# Route to LAN2 - push to client
route 10.20.0.0 255.255.255.0

# Listen configuration
proto udp
port 1194
local 172.18.0.11

# PKI files
ca /etc/openvpn/ca.crt
cert /etc/openvpn/router1.crt
key /etc/openvpn/router1.key
dh /etc/openvpn/dh.pem
tls-auth /etc/openvpn/ta.key 0

# Security
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2

# Logging
verb 4
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log

# Performance
keepalive 10 120
persist-key
persist-tun
```

### Task 4.2: Configure OpenVPN Client (Router2)
**Duration:** 30 minutes

**Actions:**
- Create client configuration file
- Point to server endpoint
- Configure tunnel interface
- Set routing for LAN1 subnet

**File:** `configs/router2/openvpn/client.conf`

**Key configuration parameters:**
```conf
# Network settings
dev tun0
dev-type tun

# Client mode
client
tls-client

# Tunnel addressing
ifconfig 10.8.0.2 10.8.0.1

# Route to LAN1
route 10.10.0.0 255.255.255.0

# Server connection
remote 172.18.0.11 1194
proto udp

# PKI files
ca /etc/openvpn/ca.crt
cert /etc/openvpn/router2.crt
key /etc/openvpn/router2.key
tls-auth /etc/openvpn/ta.key 1

# Security (must match server)
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2

# Logging
verb 4
log-append /var/log/openvpn.log

# Performance
keepalive 10 120
persist-key
persist-tun
resolv-retry infinite
nobind
```

---

## Phase 5: Routing Configuration

### Task 5.1: Configure Router1 Routing
**Duration:** 20 minutes

**Actions:**
- Add static route to LAN2 via tunnel
- Configure iptables for NAT/forwarding
- Enable masquerading if needed

**Commands to execute in router1:**
```bash
# Add route to LAN2 via tun0
ip route add 10.20.0.0/24 via 10.8.0.2 dev tun0

# Enable IP forwarding (should be in sysctl)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Configure iptables
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -s 10.10.0.0/24 -d 10.20.0.0/24 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
```

### Task 5.2: Configure Router2 Routing
**Duration:** 20 minutes

**Actions:**
- Add static route to LAN1 via tunnel
- Configure iptables for forwarding
- Mirror router1 configuration

**Commands to execute in router2:**
```bash
# Add route to LAN1 via tun0
ip route add 10.10.0.0/24 via 10.8.0.1 dev tun0

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Configure iptables
iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -s 10.20.0.0/24 -d 10.10.0.0/24 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables/rules.v4
```

### Task 5.3: Configure Host Routes
**Duration:** 15 minutes

**Actions:**
- Ensure host1 uses router1 as default gateway
- Ensure host2 uses router2 as default gateway
- Verify routing table on both hosts

**Commands:**
```bash
# On host1
ip route add default via 10.10.0.1

# On host2
ip route add default via 10.20.0.1
```

---

## Phase 6: Startup and Initialization

### Task 6.1: Create Startup Scripts
**Duration:** 30 minutes

**Actions:**
- Create entrypoint scripts for routers
- Automate OpenVPN startup
- Automate routing configuration

**File:** `scripts/router1-entrypoint.sh`
```bash
#!/bin/bash

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Start OpenVPN
openvpn --config /etc/openvpn/server.conf --daemon

# Wait for tun0 interface
sleep 5

# Configure routing
ip route add 10.20.0.0/24 via 10.8.0.2 dev tun0

# Configure iptables
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Keep container running
tail -f /var/log/openvpn.log
```

**File:** `scripts/router2-entrypoint.sh`
```bash
#!/bin/bash

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Start OpenVPN
openvpn --config /etc/openvpn/client.conf --daemon

# Wait for tun0 interface
sleep 5

# Configure routing
ip route add 10.10.0.0/24 via 10.8.0.1 dev tun0

# Configure iptables
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Keep container running
tail -f /var/log/openvpn.log
```

### Task 6.2: Update docker-compose.yml with Entrypoints
**Duration:** 15 minutes

**Actions:**
- Mount startup scripts into containers
- Configure command to execute scripts
- Ensure proper script permissions

---

## Phase 7: Testing and Verification

### Task 7.1: Basic Connectivity Tests
**Duration:** 30 minutes

**Test sequence:**

1. **Verify OpenVPN tunnel establishment:**
   ```bash
   # On router1
   docker exec router1 cat /var/log/openvpn-status.log
   docker exec router1 ip addr show tun0
   
   # On router2
   docker exec router2 ip addr show tun0
   ```

2. **Test router-to-router connectivity:**
   ```bash
   # From router1
   docker exec router1 ping -c 4 10.8.0.2
   
   # From router2
   docker exec router2 ping -c 4 10.8.0.1
   ```

3. **Verify routing tables:**
   ```bash
   docker exec router1 ip route
   docker exec router2 ip route
   docker exec host1 ip route
   docker exec host2 ip route
   ```

4. **Test LAN connectivity:**
   ```bash
   # From host1 to router1
   docker exec host1 ping -c 4 10.10.0.1
   
   # From host2 to router2
   docker exec host2 ping -c 4 10.20.0.1
   ```

5. **PRIMARY TEST - Host-to-host connectivity:**
   ```bash
   # From host1 to host2
   docker exec host1 ping -c 10 10.20.0.10
   
   # From host2 to host1
   docker exec host2 ping -c 10 10.10.0.10
   ```

**Success criteria:**
- All pings successful with 0% packet loss
- Round-trip time reasonable (< 10ms in local Docker environment)

### Task 7.2: Encryption Verification
**Duration:** 30 minutes

**Test 1: Capture unencrypted traffic on LAN side**
```bash
# On router1, capture traffic on LAN interface
docker exec router1 tcpdump -i eth0 -n 'icmp and src 10.10.0.10 and dst 10.20.0.10' -w /tmp/lan-traffic.pcap

# Trigger ping from host1
docker exec host1 ping -c 5 10.20.0.10

# Analyze capture - should see clear ICMP packets
docker exec router1 tcpdump -r /tmp/lan-traffic.pcap -v
```

**Test 2: Capture encrypted traffic on public network**
```bash
# On router1, capture traffic on public interface
docker exec router1 tcpdump -i eth1 -n 'udp port 1194' -w /tmp/vpn-traffic.pcap

# Trigger ping from host1
docker exec host1 ping -c 5 10.20.0.10

# Analyze capture - should see OpenVPN UDP packets, no clear ICMP
docker exec router1 tcpdump -r /tmp/vpn-traffic.pcap -v -X
```

**Test 3: Verify encryption in OpenVPN logs**
```bash
# Check OpenVPN logs for cipher information
docker exec router1 grep -i "cipher" /var/log/openvpn.log
docker exec router2 grep -i "cipher" /var/log/openvpn.log

# Verify TLS handshake
docker exec router1 grep -i "tls" /var/log/openvpn.log
```

**Success criteria:**
- ICMP packets visible on LAN interfaces (unencrypted)
- No ICMP packets visible in public network capture (encrypted)
- Only OpenVPN UDP packets visible on public network
- Logs confirm AES-256-GCM cipher usage
- TLS 1.2+ handshake successful

### Task 7.3: Create Automated Verification Script
**Duration:** 30 minutes

**File:** `scripts/verify-connectivity.sh`
```bash
#!/bin/bash

echo "=== VPN Tunnel Connectivity Verification ==="

# Test 1: Tunnel interfaces
echo -e "\n1. Checking tunnel interfaces..."
docker exec router1 ip addr show tun0 && echo "✓ Router1 tun0 UP" || echo "✗ Router1 tun0 DOWN"
docker exec router2 ip addr show tun0 && echo "✓ Router2 tun0 UP" || echo "✗ Router2 tun0 DOWN"

# Test 2: Router ping
echo -e "\n2. Testing router-to-router ping..."
docker exec router1 ping -c 3 -W 2 10.8.0.2 > /dev/null && echo "✓ Router1 → Router2 OK" || echo "✗ Router1 → Router2 FAILED"

# Test 3: Host ping
echo -e "\n3. Testing host-to-host ping..."
docker exec host1 ping -c 3 -W 2 10.20.0.10 > /dev/null && echo "✓ Host1 → Host2 OK" || echo "✗ Host1 → Host2 FAILED"
docker exec host2 ping -c 3 -W 2 10.10.0.10 > /dev/null && echo "✓ Host2 → Host1 OK" || echo "✗ Host2 → Host1 FAILED"

echo -e "\n=== Verification Complete ==="
```

### Task 7.4: Create Encryption Verification Script
**Duration:** 20 minutes

**File:** `scripts/verify-encryption.sh`
```bash
#!/bin/bash

echo "=== VPN Encryption Verification ==="

# Start capture on public interface
echo "Starting packet capture on public network..."
docker exec -d router1 tcpdump -i eth1 -n 'udp port 1194' -w /tmp/vpn-capture.pcap -c 50

# Generate traffic
echo "Generating test traffic..."
docker exec host1 ping -c 10 10.20.0.10 > /dev/null

# Wait for capture
sleep 3

# Analyze
echo -e "\nAnalyzing captured packets..."
ICMP_COUNT=$(docker exec router1 tcpdump -r /tmp/vpn-capture.pcap 2>/dev/null | grep -c ICMP)
OPENVPN_COUNT=$(docker exec router1 tcpdump -r /tmp/vpn-capture.pcap 2>/dev/null | grep -c "UDP.*1194")

echo "ICMP packets found in VPN traffic: $ICMP_COUNT"
echo "OpenVPN packets found: $OPENVPN_COUNT"

if [ "$ICMP_COUNT" -eq 0 ] && [ "$OPENVPN_COUNT" -gt 0 ]; then
    echo -e "\n✓ Traffic is ENCRYPTED (no visible ICMP, OpenVPN packets present)"
else
    echo -e "\n✗ WARNING: Traffic may not be properly encrypted!"
fi

# Check cipher
echo -e "\nVerifying cipher configuration..."
docker exec router1 grep "cipher.*AES-256-GCM" /var/log/openvpn.log && echo "✓ AES-256-GCM cipher confirmed" || echo "⚠ Cipher verification failed"

echo -e "\n=== Encryption Verification Complete ==="
```

---

## Phase 8: Troubleshooting Preparation

### Task 8.1: Common Issues and Solutions
**Duration:** N/A (Reference)

**Issue 1: Tunnel doesn't establish**
- Check OpenVPN logs: `/var/log/openvpn.log`
- Verify certificates are correct and not expired
- Ensure router1 and router2 can reach each other on 172.18.0.0/24
- Check firewall rules (iptables)
- Verify /dev/net/tun device is available

**Issue 2: Tunnel up but no routing**
- Check routing tables on both routers
- Verify IP forwarding is enabled: `cat /proc/sys/net/ipv4/ip_forward`
- Check iptables FORWARD chain rules
- Verify tun0 interface has correct IP addresses

**Issue 3: Can ping routers but not hosts**
- Check host default gateways
- Verify routing tables on hosts
- Check iptables rules on routers
- Ensure hosts have correct network configuration

**Issue 4: Connectivity works but encryption fails verification**
- Check OpenVPN cipher configuration on both sides
- Verify TLS version compatibility
- Ensure ta.key direction is correct (0 on server, 1 on client)

### Task 8.2: Debugging Commands Reference
**Duration:** N/A (Reference)

```bash
# Check container status
docker-compose ps

# View OpenVPN logs
docker exec router1 tail -f /var/log/openvpn.log
docker exec router2 tail -f /var/log/openvpn.log

# Check tunnel interface
docker exec router1 ip addr show tun0
docker exec router1 ip link show tun0

# View routing table
docker exec router1 ip route
docker exec router1 route -n

# Check IP forwarding
docker exec router1 cat /proc/sys/net/ipv4/ip_forward

# View iptables rules
docker exec router1 iptables -L -v -n
docker exec router1 iptables -t nat -L -v -n

# Test connectivity step by step
docker exec host1 ping 10.10.0.1        # Gateway
docker exec host1 ping 172.18.0.11      # Router public IP
docker exec host1 ping 10.8.0.1         # Tunnel endpoint
docker exec host1 ping 10.20.0.1        # Remote gateway
docker exec host1 ping 10.20.0.10       # Remote host

# Trace route
docker exec host1 traceroute 10.20.0.10

# Capture traffic
docker exec router1 tcpdump -i tun0 -n
docker exec router1 tcpdump -i eth1 -n 'udp port 1194'

# Check OpenVPN status
docker exec router1 cat /var/log/openvpn-status.log
```

---

## Phase 9: Documentation and Cleanup

### Task 9.1: Create Usage Documentation
**Duration:** 45 minutes

Create README.md with:
- Project description
- Prerequisites
- Setup instructions
- Testing procedures
- Troubleshooting guide
- Network diagram

### Task 9.2: Create Cleanup Scripts
**Duration:** 15 minutes

**File:** `scripts/cleanup.sh`
```bash
#!/bin/bash

echo "Stopping containers..."
docker-compose down

echo "Removing volumes..."
docker volume prune -f

echo "Cleanup complete"
```

---

## Timeline Summary

| Phase                               | Duration  | Cumulative |
| ----------------------------------- | --------- | ---------- |
| Phase 1: Environment Preparation    | 15 min    | 15 min     |
| Phase 2: PKI Setup                  | 1.5 hours | 1h 45m     |
| Phase 3: Docker Infrastructure      | 2 hours   | 3h 45m     |
| Phase 4: OpenVPN Configuration      | 1 hour    | 4h 45m     |
| Phase 5: Routing Configuration      | 55 min    | 5h 40m     |
| Phase 6: Startup and Initialization | 45 min    | 6h 25m     |
| Phase 7: Testing and Verification   | 2 hours   | 8h 25m     |
| Phase 8: Troubleshooting Prep       | 30 min    | 8h 55m     |
| Phase 9: Documentation              | 1 hour    | 9h 55m     |

**Total Estimated Time:** ~10 hours (including contingency)

---

## Prerequisites and Dependencies

### Software Requirements
- Docker Engine 20.10+
- Docker Compose 1.29+
- Git (optional)
- OpenVPN 2.5+
- Easy-RSA 3.0+

### Knowledge Requirements
- Docker and containerization concepts
- Linux networking fundamentals
- OpenVPN configuration
- PKI and certificate management
- iptables and routing
- Basic shell scripting

### System Requirements
- Linux host (or Windows with WSL2)
- /dev/net/tun support
- Sufficient privileges for Docker and networking

---

## Success Metrics

1. ✓ All containers running and healthy
2. ✓ OpenVPN tunnel established (tun0 interfaces up on both routers)
3. ✓ Successful ping from host1 (10.10.0.10) to host2 (10.20.0.10)
4. ✓ Successful ping from host2 (10.20.0.10) to host1 (10.10.0.10)
5. ✓ Zero packet loss in connectivity tests
6. ✓ No visible ICMP packets in public network captures
7. ✓ OpenVPN packets encrypted with AES-256-GCM
8. ✓ TLS 1.2+ handshake verified in logs

---

## Next Steps After Completion

1. Experiment with different encryption algorithms
2. Implement client-to-client communication
3. Add monitoring with Prometheus/Grafana
4. Implement failover scenarios
5. Test performance under load
6. Document security best practices
7. Create automated deployment pipeline

---

## References

- OpenVPN Documentation: https://openvpn.net/community-resources/
- Docker Networking: https://docs.docker.com/network/
- Easy-RSA: https://github.com/OpenVPN/easy-rsa
- iptables Guide: https://www.netfilter.org/documentation/
