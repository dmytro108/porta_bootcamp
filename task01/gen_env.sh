#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo -e "${YELLOW}Generating compose/.env from task01.env.sh...${NC}"

if [ -f "$PROJECT_ROOT/task01.env.sh" ]; then
    if [ -f "$PROJECT_ROOT/compose/.env" ]; then
        echo -e "${GREEN}\tCompose settings $PROJECT_ROOT/compose/.env already exist. Skipping generation.${NC}"
    else
        bash "$PROJECT_ROOT/task01.env.sh" > "$PROJECT_ROOT/compose/.env"
        echo -e "${GREEN}\tCreated $PROJECT_ROOT/compose/.env${NC}"
    fi
else
    echo -e "${RED}\tError: task01.env.sh file not found at $PROJECT_ROOT/task01.env.sh${NC}"
    exit 1
fi
