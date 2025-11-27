# VPN Tunnel Lab - OpenVPN Site-to-Site

## Project Description

This project implements a site-to-site OpenVPN tunnel between two LANs using Docker containers to emulate the complete network topology. The setup demonstrates certificate-based authentication, encrypted tunneling, and inter-LAN routing.

## Network Topology

```
┌─────────────────┐                                    ┌─────────────────┐
│     LAN 1       │                                    │     LAN 2       │
│  10.10.0.0/24   │                                    │  10.20.0.0/24   │
│                 │                                    │                 │
│  ┌──────────┐   │                                    │   ┌──────────┐  │
│  │  host1   │   │                                    │   │  host2   │  │
│  │10.10.0.10│   │                                    │   │10.20.0.10│  │
│  └────┬─────┘   │                                    │   └────┬─────┘  │
│       │         │                                    │        │        │
│  ┌────┴─────┐   │    ┌──────────────────────┐       │   ┌────┴─────┐  │
│  │ router1  │───┼────│   Public Network     │───────┼───│ router2  │  │
│  │10.10.0.1 │   │    │   172.18.0.0/24      │       │   │10.20.0.1 │  │
│  │172.18.0.11   │    │                      │       │   │172.18.0.12  │
│  └──────────┘   │    │  OpenVPN Tunnel      │       │   └──────────┘  │
│                 │    │  (10.8.0.1-10.8.0.2) │       │                 │
└─────────────────┘    └──────────────────────┘       └─────────────────┘
```

### Network Details

- **LAN1:** 10.10.0.0/24
  - host1: 10.10.0.10
  - router1 (LAN interface): 10.10.0.1
  
- **LAN2:** 10.20.0.0/24
  - host2: 10.20.0.10
  - router2 (LAN interface): 10.20.0.1
  
- **Public Network:** 172.18.0.0/24
  - router1 (public interface): 172.18.0.11
  - router2 (public interface): 172.18.0.12
  
- **VPN Tunnel:** TUN interface (Layer 3)
  - router1 (tunnel): 10.8.0.1
  - router2 (tunnel): 10.8.0.2

## Objectives

1. Setup OpenVPN site-to-site tunnel between router1 and router2
2. Enable routing between LAN1 and LAN2 (10.10.0.0/24 ↔ 10.20.0.0/24)
3. Use certificate-based authentication
4. Emulate all networks using Docker and docker-compose

## Success Criteria

- ✓ Successful ping from host1 (10.10.0.10) to host2 (10.20.0.10)
- ✓ Successful ping from host2 (10.20.0.10) to host1 (10.10.0.10)
- ✓ Traffic encryption verification (no visible plaintext ICMP on public network)
- ✓ Zero packet loss in connectivity tests

## Project Structure

```
task04/
├── docker-compose.yml          # Docker Compose configuration
├── Dockerfile.router           # Router container image
├── Dockerfile.host             # Host container image
├── configs/
│   ├── router1/
│   │   ├── openvpn/           # OpenVPN server configuration
│   │   └── network/           # Network configuration
│   └── router2/
│       ├── openvpn/           # OpenVPN client configuration
│       └── network/           # Network configuration
├── pki/
│   ├── ca/                    # Certificate Authority files
│   ├── certs/                 # Certificates
│   └── keys/                  # Private keys
├── scripts/
│   ├── setup-pki.sh           # PKI setup automation
│   ├── verify-connectivity.sh # Connectivity testing
│   └── verify-encryption.sh   # Encryption verification
├── plan.md                     # Implementation plan
└── PROJECT_README.md          # This file
```

## Prerequisites

### Software Requirements
- Docker Engine 20.10+
- Docker Compose 1.29+ (or Docker Compose v2)
- OpenVPN 2.5+ (for PKI setup)
- Easy-RSA 3.0+ (for certificate generation)

### System Requirements
- Linux host, macOS, or Windows with WSL2
- /dev/net/tun support
- Sufficient privileges for Docker and networking operations

### Knowledge Requirements
- Basic Docker and containerization concepts
- Linux networking fundamentals
- Understanding of OpenVPN and VPNs
- PKI and certificate management basics
- iptables and routing concepts

## Implementation Phases

This project is implemented in multiple phases:

1. **Phase 1: Environment Preparation** ✓ (Current)
   - Directory structure setup
   - Initial documentation
   
2. **Phase 2: PKI Setup**
   - Certificate Authority creation
   - Server and client certificates
   - DH parameters and TLS-auth keys
   
3. **Phase 3: Docker Infrastructure**
   - Docker networks configuration
   - Dockerfiles for routers and hosts
   - docker-compose.yml setup
   
4. **Phase 4: OpenVPN Configuration**
   - Server configuration (router1)
   - Client configuration (router2)
   
5. **Phase 5: Routing Configuration**
   - Static routes setup
   - iptables forwarding rules
   
6. **Phase 6: Startup and Initialization**
   - Entrypoint scripts
   - Automated startup configuration
   
7. **Phase 7: Testing and Verification**
   - Connectivity tests
   - Encryption verification
   - Automated test scripts
   
8. **Phase 8: Troubleshooting Preparation**
   - Common issues documentation
   - Debugging procedures
   
9. **Phase 9: Documentation and Cleanup**
   - Final documentation
   - Cleanup scripts

## Quick Start (After Full Implementation)

```bash
# 1. Setup PKI (certificates)
cd pki/
./scripts/setup-pki.sh

# 2. Start the environment
docker-compose up -d

# 3. Verify connectivity
./scripts/verify-connectivity.sh

# 4. Verify encryption
./scripts/verify-encryption.sh
```

## Testing

### Basic Connectivity Test
```bash
# Test from host1 to host2
docker exec host1 ping -c 5 10.20.0.10

# Test from host2 to host1
docker exec host2 ping -c 5 10.10.0.10
```

### Verify VPN Tunnel
```bash
# Check tunnel interface on router1
docker exec router1 ip addr show tun0

# Check tunnel interface on router2
docker exec router2 ip addr show tun0

# View OpenVPN status
docker exec router1 cat /var/log/openvpn-status.log
```

### Verify Encryption
```bash
# Run the automated encryption verification
./scripts/verify-encryption.sh
```

## Troubleshooting

### Check Container Status
```bash
docker-compose ps
```

### View OpenVPN Logs
```bash
# Router1 (server)
docker exec router1 tail -f /var/log/openvpn.log

# Router2 (client)
docker exec router2 tail -f /var/log/openvpn.log
```

### Check Routing
```bash
# Router1 routing table
docker exec router1 ip route

# Host1 routing table
docker exec host1 ip route
```

### Interactive Debugging
```bash
# Access router1 shell
docker exec -it router1 /bin/bash

# Access host1 shell
docker exec -it host1 /bin/bash
```

## Security Considerations

- Certificate-based authentication (mutual TLS)
- AES-256-GCM encryption for data channel
- SHA256 authentication
- TLS 1.2+ for control channel
- TLS-auth for additional HMAC verification
- Proper file permissions on private keys

## References

- [OpenVPN Documentation](https://openvpn.net/community-resources/)
- [Docker Networking Guide](https://docs.docker.com/network/)
- [Easy-RSA Documentation](https://github.com/OpenVPN/easy-rsa)
- [iptables Tutorial](https://www.netfilter.org/documentation/)

## License

Educational project for learning purposes.

## Author

Created as part of Porta Bootcamp Task 04
