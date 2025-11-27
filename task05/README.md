# Task

## Network topology

Given two LANs:
  - LAN1: 10.10.0.0/24, host1 10.10.0.10
  - LAN2: 10.20.0.0/24, host2 10.20.0.10
and a "public" network: 172.18.0.0/24

Each LAN has a router:
  - router1: 
    - LAN1 interface: 10.10.0.1
    - "public" interface: 172.18.0.11

  - router2:
    - LAN2 interface: 10.20.0.1
    - "public" interface: 172.18.0.12

## Objectives

Setup VPN tunnel (tun0 (TUN, L3)) between router1 and router2 to enable routing between LAN1 and LAN2 (10.10.0.0/24 ↔ 10.20.0.0/24).

### Constraints

  - OpenVPN Site-to-site tunnel with certificates based authentification 
  - Emulate all suntets (LAN1, LAN2, public) and all hosts and routers with Docker and docker-compose.

## Result

- Succsefull ping between host1 and host2
- Make sure traffik is encrypted