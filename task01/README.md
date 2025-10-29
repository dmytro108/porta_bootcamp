# Task 01: Docker + LAMP + Nagios

## Theory
Familiarize yourself with the basics of Docker and Docker Compose:
- What is a container, image, volume, network
- How Compose works and how to run multi-container applications

## Practice (Docker Compose)
### Set up a LAMP stack:
- Apache + PHP on port 9022
- MySQL master + MySQL slave with configured replication:
  - Writes go to the master
  - Reads go to the slave
- index.php should be located on the host and mounted into the Apache container

### Monitoring
- Deploy a Nagios container and configure monitoring for:
  - Apache: port and availability
  - MySQL: availability of master/slave, replication status, and database presence

---

## Solution

### Install:
```shell
# Git
sudo dnf install git

# Docker
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo systemctl start docker
sudo groupadd docker
sudo usermod -aG docker $USER
```

