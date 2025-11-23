#!/bin/bash

#############################################################################
# run-in-container.sh - Wrapper to run task03 scripts inside db_master container
#############################################################################
# This script executes task03 scripts inside the db_master container where
# MySQL is accessible and the task03 directory is mounted at /home
#
# Usage:
#   ./run-in-container.sh <script> [args...]
#
# Examples:
#   ./run-in-container.sh db-load.sh --rows 100000
#   ./run-in-container.sh db-cleanup.sh
#############################################################################

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <script> [args...]" >&2
    echo "" >&2
    echo "Available scripts:" >&2
    echo "  db-load.sh        - Load test data into tables" >&2
    echo "  db-cleanup.sh     - Run cleanup benchmarks" >&2
    echo "  db-partition-maintenance.sh - Maintain partitions" >&2
    exit 1
fi

SCRIPT="$1"
shift

# Load environment variables from task01/compose/.env
ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Environment file not found: $ENV_FILE" >&2
    exit 1
fi

# Export variables so they're available in the container
set -a
source "$ENV_FILE"
set +a

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "ERROR: Container ${CONTAINER_NAME} is not running" >&2
    echo "       Start it with: cd task01/compose && docker compose up -d" >&2
    exit 1
fi

# Execute the script inside the container
echo "Executing ${SCRIPT} inside ${CONTAINER_NAME} container..."
echo ""

# Pass environment variables to the container
docker exec -i "${CONTAINER_NAME}" bash -c "
export DB_MASTER_HOST='${DB_MASTER_HOST}'
export DB_SLAVE_HOST='${DB_SLAVE_HOST}'
export CLEANUP_USER='${CLEANUP_USER}'
export CLEANUP_PASSW='${CLEANUP_PASSW}'
cd ${SCRIPT_DIR} && ./${SCRIPT} $*
"
