# Network Configuration (Infrastructure as Code)

This directory contains declarative configuration files for the VPN routers, following Infrastructure as Code (IaC) principles.

## Directory Structure

```
configs/
├── router1/
│   ├── network/
│   │   ├── iptables.rules  # Firewall rules
│   │   └── routes.conf     # Static routing configuration
│   └── openvpn/            # OpenVPN server configuration
└── router2/
    ├── network/
    │   ├── iptables.rules  # Firewall rules
    │   └── routes.conf     # Static routing configuration
    └── openvpn/            # OpenVPN client configuration
```

## Configuration Files

### iptables.rules

Declarative firewall rules in `iptables-restore` format. These rules are loaded at container startup using `iptables-restore -n`.

**Format:**
```
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

-A FORWARD -i tun0 -j ACCEPT
# ... more rules ...

COMMIT
```

**Features:**
- Clean, declarative syntax
- Version control friendly
- Atomic application (all-or-nothing)
- No duplicate rule issues

### routes.conf

Static routes to be applied after VPN tunnel establishment.

**Format:**
```
# destination via gateway dev interface
10.20.0.0/24 via 10.8.0.2 dev tun0
```

**Features:**
- One route per line
- Comments start with `#`
- Empty lines are ignored
- Routes are applied in order

## Usage

### Modifying iptables Rules

1. Edit the appropriate `iptables.rules` file
2. Test syntax: `iptables-restore -t < configs/router1/network/iptables.rules`
3. Restart container: `docker compose restart router1`

### Adding Static Routes

1. Edit the appropriate `routes.conf` file
2. Add routes in the format: `<destination> via <gateway> dev <interface>`
3. Restart container: `docker compose restart router1`

### Viewing Active Configuration

```bash
# View iptables rules
docker exec router1 iptables -L -v -n

# View routing table
docker exec router1 ip route
```

## Benefits of IaC Approach

1. **Declarative Configuration**: Define desired state, not imperative commands
2. **Version Control**: Track changes to network configuration over time
3. **Reproducibility**: Same configuration produces same results
4. **Documentation**: Configuration files serve as living documentation
5. **Testing**: Can validate syntax without applying changes
6. **Separation of Concerns**: Network config separated from startup logic
7. **Easy Maintenance**: Modify files instead of editing scripts

## Integration with Docker

Configuration files are mounted as read-only volumes:

```yaml
volumes:
  - ./configs/router1/network:/etc/network
```

The entrypoint scripts load configuration at startup:
- `iptables-restore -n < /etc/network/iptables.rules`
- Parse and apply routes from `/etc/network/routes.conf`

## Notes

- Most routes are automatically configured by OpenVPN
- Custom routes in `routes.conf` are typically only needed for:
  - Static routes not advertised via VPN
  - Manual override of automatic routing
  - Special routing policies
  
- The default `routes.conf` files have all routes commented out because OpenVPN handles routing automatically via:
  - Server: `route` directive + `ccd/router2` `iroute` 
  - Client: `route` directive pushed from server
