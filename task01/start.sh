#!/bin/bash

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Docker Compose setup...${NC}"

# Optional: remap user/group IDs on the host before starting containers
# Usage: start.sh [TARGET_UID] [TARGET_GID]
TARGET_UID="$1"
TARGET_GID="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

"$PROJECT_ROOT/remap_ids.sh" "${TARGET_UID}" "${TARGET_GID}" || true

"$PROJECT_ROOT/gen_env.sh"
"$PROJECT_ROOT/gen_certs.sh"

echo -e "${YELLOW}Starting Docker Compose...${NC}"
cd "$PROJECT_ROOT/compose"
docker compose up -d

echo -e "${GREEN}Docker Compose started successfully!${NC}"
echo -e "${YELLOW}Use 'docker compose ps' to check container status${NC}"
