#!/bin/bash

# =====================================================
# Database Schema Creation Script
# =====================================================
# This script creates the cleanup_bench database schema
# using credentials from .env file
# =====================================================

set -e  # Exit on error

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load helper functions
if [ ! -f "${SCRIPT_DIR}/lib/helpers.sh" ]; then
    echo "Error: lib/helpers.sh not found"
    exit 1
fi
source "${SCRIPT_DIR}/lib/helpers.sh"

# Load environment variables from .env file
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE"
    echo "Please create a .env file based on .env.example"
    exit 1
fi

# Source the .env file
source "$ENV_FILE"

# Validate required variables
REQUIRED_VARS=("DB_HOST" "DB_PORT" "DB_ROOT_USER" "DB_ROOT_PASSWORD" "DB_USER" "DB_PASSWORD" "DB_NAME")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        log_error "$var is not set in .env file"
        exit 1
    fi
done

log "=================================================="
log "Creating Database Schema"
log "=================================================="
log "Host: $DB_HOST:$DB_PORT"
log "Database: $DB_NAME"
log "Application User: $DB_USER"
log "=================================================="
echo ""

# Prepare the SQL file with user credentials
TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

# Read the schema file and replace user credentials
sed -e "s/'cleanup_admin'@'%'/'${DB_USER}'@'%'/g" \
    -e "s/IDENTIFIED BY 'cleanup_pass123'/IDENTIFIED BY '${DB_PASSWORD}'/g" \
    "${SCRIPT_DIR}/db-schema.sql" > "$TEMP_SQL"

# Execute the SQL script
log "Executing database schema creation..."
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" < "$TEMP_SQL"

if [ $? -eq 0 ]; then
    echo ""
    log "=================================================="
    log "✓ Database schema created successfully!"
    log "=================================================="
    log "Database: $DB_NAME"
    log "User: $DB_USER"
    log "Host: $DB_HOST:$DB_PORT"
    log "=================================================="
    echo ""
    echo "You can now connect using:"
    echo "mysql -h$DB_HOST -P$DB_PORT -u$DB_USER -p$DB_PASSWORD $DB_NAME"
    echo ""
else
    echo ""
    log_error "=================================================="
    log_error "✗ Error creating database schema"
    log_error "=================================================="
    exit 1
fi
