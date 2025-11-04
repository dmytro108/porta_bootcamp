#!/bin/bash

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Docker Compose setup...${NC}"

# Get the script directory
SCRIPT_DIR="$(pwd)"
PROJECT_ROOT="$(pwd)"

# Export environment variables first
echo -e "${YELLOW}Step 1: Exporting environment variables...${NC}"
cd "$PROJECT_ROOT/compose"
if [ -f "task01.env" ]; then
    set -a
    source task01.env
    set +a
    echo -e "${GREEN}Environment variables loaded from task01.env${NC}"
else
    echo -e "${RED}Warning: task01.env file not found!${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 2: Generating certificates for MySQL servers...${NC}"

# Generate CA key and cert
echo "Generating CA certificate..."
cd "$PROJECT_ROOT/db"
openssl genrsa 2048 > ca-key.pem
openssl req -new -x509 -nodes -days 3650 -key ca-key.pem -out ca-cert.pem -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/CN=${CA_CN}"

# Generate server key and CSR, sign by CA
echo "Generating master server certificate..."
cd "$PROJECT_ROOT/db/master/tls"
openssl req -newkey rsa:2048 -days 3650 -nodes -keyout server-key.pem -out server-req.pem -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/CN=${MASTER_CN}"
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 3650 -CA $PROJECT_ROOT/db/ca-cert.pem -CAkey $PROJECT_ROOT/db/ca-key.pem -set_serial 01 -out server-cert.pem
chmod 400 server-key.pem
sudo chown 999:999 server-key.pem

# Generate client key and CSR, sign by CA
echo "Generating slave client certificate..."
cd "$PROJECT_ROOT/db/slave/tls"
openssl req -newkey rsa:2048 -days 3650 -nodes -keyout client-key.pem -out client-req.pem -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/CN=${SLAVE_CN}"
openssl rsa -in client-key.pem -out client-key.pem
openssl x509 -req -in client-req.pem -days 3650 -CA $PROJECT_ROOT/db/ca-cert.pem -CAkey $PROJECT_ROOT/db/ca-key.pem -set_serial 01 -out client-cert.pem
chmod 400 client-key.pem
sudo chown 999:999 client-key.pem

echo -e "${GREEN}Certificates generated successfully!${NC}"

# Start Docker Compose
echo -e "${YELLOW}Step 3: Starting Docker Compose...${NC}"
cd $PROJECT_ROOT/compose
docker compose up -d

echo -e "${GREEN}Docker Compose started successfully!${NC}"
echo -e "${YELLOW}Use 'docker compose ps' to check container status${NC}"
