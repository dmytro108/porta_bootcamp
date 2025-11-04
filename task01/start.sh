#!/bin/bash

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Docker Compose setup...${NC}"

# Resolve project root to the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Step 1: Load TLS subject variables from tls.env
echo -e "${YELLOW}Step 1: Loading TLS variables from tls.env...${NC}"
if [ -f "$PROJECT_ROOT/tls.env" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/tls.env"
    echo -e "${GREEN}TLS variables loaded from tls.env${NC}"
else
    echo -e "${RED}Error: tls.env file not found at $PROJECT_ROOT/tls.env${NC}"
    exit 1
fi

# Step 2: Generate compose/.env using task01.env.sh
echo -e "${YELLOW}Step 2: Generating compose/.env from task01.env.sh...${NC}"
if [ -f "$PROJECT_ROOT/task01.env.sh" ]; then
    # mkdir -p "$PROJECT_ROOT/compose"
    # Execute the generator script and write key=value lines into compose/.env
    bash "$PROJECT_ROOT/task01.env.sh" > "$PROJECT_ROOT/compose/.env"
    echo -e "${GREEN}Created $PROJECT_ROOT/compose/.env${NC}"
else
    echo -e "${RED}Error: task01.env.sh file not found at $PROJECT_ROOT/task01.env.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 3: Checking/Generating certificates for MySQL servers...${NC}"

# Check if certificates already exist
CA_CERT="$PROJECT_ROOT/db/ca-cert.pem"
CA_KEY="$PROJECT_ROOT/db/ca-key.pem"
MASTER_CERT="$PROJECT_ROOT/db/master/tls/server-cert.pem"
MASTER_KEY="$PROJECT_ROOT/db/master/tls/server-key.pem"
SLAVE_CERT="$PROJECT_ROOT/db/slave/tls/client-cert.pem"
SLAVE_KEY="$PROJECT_ROOT/db/slave/tls/client-key.pem"

if [ -f "$CA_CERT" ] && [ -f "$CA_KEY" ] && [ -f "$MASTER_CERT" ] && [ -f "$MASTER_KEY" ] && [ -f "$SLAVE_CERT" ] && [ -f "$SLAVE_KEY" ]; then
    echo -e "${GREEN}TLS certificates already exist. Skipping generation.${NC}"
else
    echo "TLS certificates not found. Generating new certificates..."
    
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
fi

# Start Docker Compose
echo -e "${YELLOW}Step 4: Starting Docker Compose...${NC}"
cd "$PROJECT_ROOT/compose"
docker compose up -d

echo -e "${GREEN}Docker Compose started successfully!${NC}"
echo -e "${YELLOW}Use 'docker compose ps' to check container status${NC}"
