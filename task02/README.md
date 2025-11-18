# Task 02: IPTables - Protection and Traffic Analysis
## Part 1: Theory
Study the basics of iptables:
  -  Chains: INPUT, OUTPUT, FORWARD
  -  Policies: ACCEPT, DROP, REJECT
  -  Creating and using custom chains
  -  Filtering by IP, port, protocol, interface
  -  Logging and connection limiting
  -  Usage of iptables-save, iptables-restore

## Part 2: Practice

Your server is under a brute-force attack on a specific port (e.g., 22/SSH) from various IPs.

Implement iptables rules to:
  -  Protect the server from such attacks
  -  Allow analysis of traffic sources