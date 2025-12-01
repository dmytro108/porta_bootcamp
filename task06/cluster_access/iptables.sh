sudo iptables -t nat -N MINIKUBE
sudo iptables -t nat -I MINIKUBE -p tcp -i ens18 --dport 80 -j DNAT --to-destination $(minikube ip):30080
sudo iptables -t nat -I MINIKUBE -p tcp -i ens18 --dport 443 -j DNAT --to-destination $(minikube ip):30443
sudo iptables -t nat -I MINIKUBE -p tcp -i ens18 --dport 9090 -j DNAT --to-destination $(minikube ip):30090
sudo iptables -t nat -I PREROUTING -p tcp -i ens18  -j MINIKUBE

sudo iptables -N MINIKUBE
sudo iptables -I MINIKUBE -p tcp -d $(minikube ip) --dport 30080 -j ACCEPT
sudo iptables -I MINIKUBE -p tcp -d $(minikube ip) --dport 30443 -j ACCEPT
sudo iptables -I MINIKUBE -p tcp -d $(minikube ip) --dport 30090 -j ACCEPT
sudo iptables -I FORWARD -p tcp -d $(minikube ip)  -j MINIKUBE
