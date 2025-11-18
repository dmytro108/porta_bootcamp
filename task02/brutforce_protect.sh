### Create IP whitelist
sudo ipset create my_subnets hash:ip
sudo ipset add my_subnets 192.168.137.0/28
sudo ipset list my_subnets

### Clean table filter, chain INPUT
sudo iptables -t filter -F
sudo iptables -t filter -X

### Temp policies
sudo iptables -P INPUT   ACCEPT
sudo iptables -P OUTPUT  ACCEPT
sudo iptables -P FORWARD ACCEPT

### Accept loopback
sudo iptables -t filter -A  INPUT -i lo -j ACCEPT
sudo iptables -t filter -A OUTPUT -o lo -j ACCEPT

### keep already established connections alive
sudo iptables -t filter -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED \
  -j ACCEPT

## ICMP
sudo iptables -A INPUT -p icmp -j ACCEPT

### custom chain for por 22
sudo iptables -t filter -N IN_SSH

### Accept already established conn
sudo iptables -t filter -A IN_SSH -p tcp -m tcp --dport 22 \
  -m conntrack --ctstate ESTABLISHED,RELATED \
  -j ACCEPT

### Accept from my_subnets
sudo iptables -t filter -A IN_SSH -p tcp -m tcp --dport 22 \
  -m set --match-set my_subnets src \
  -m conntrack --ctstate NEW \
  -j ACCEPT

### Log foreigners
sudo iptables -t filter -A IN_SSH -p tcp -m tcp --dport 22 \
  -m conntrack --ctstate NEW \
  -m limit --limit 5/min --limit-burst 10 \
  -j LOG \
  --log-prefix "Iptables: SSH_attack: " --log-level 6

### Enable IN_SSH chain
sudo iptables -t filter -A INPUT -p tcp -m tcp --dport 22 -j IN_SSH

### Update Default policies
sudo iptables -t filter -P INPUT DROP
sudo iptables -t filter -P FORWARD DROP
sudo iptables -t filter -P OUTPUT ACCEPT

### Backup iptables rules
sudo iptables-save > iptables.rules

### Separate log
echo ':msg, contains, "Iptables: " -/var/log/iptables.log' > /etc/rsyslog.d/iptables.conf
echo '& ~' >> /etc/rsyslog.d/iptables.conf
sudo systemctl restart rsyslog

########################################################
### Redirect port 3333 to ssh (22)
#sudo iptables -t nat -A PREROUTING --dport 3333 -p tcp \
#  -j REDIRECT --to-ports 22
