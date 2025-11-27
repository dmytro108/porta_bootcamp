#!/bin/bash
#
# generate-seeds.sh - Generate seed datasets for testing
#
# Usage:
#   ./generate-seeds.sh [OPTIONS]
#
# Options:
#   --rows N           Number of rows to generate (default: 100000)
#   --force            Force regeneration even if file exists
#   -h, --help         Show this help message
#
# Example:
#   ./generate-seeds.sh --rows 50000 --force
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"

# Default values
ROWS=100000
FORCE=0

# Ensure data directory exists
mkdir -p "$DATA_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to display help
show_help() {
    sed -n '2,/^$/p' "$0" | grep '^#' | sed 's/^# \?//'
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rows)
            ROWS="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Validate row count
if ! [[ "$ROWS" =~ ^[0-9]+$ ]] || [[ $ROWS -lt 1 ]]; then
    echo "ERROR: --rows must be a positive integer" >&2
    exit 1
fi

generate_seed_dataset() {
    local rows=$1
    local seed_file="${DATA_DIR}/events_seed.csv"
    local random_seed=42
    
    if [ -f "$seed_file" ] && [ $FORCE -eq 0 ]; then
        log "Seed dataset exists: $seed_file (use --force to regenerate)"
        return 0
    fi
    
    log "Generating seed dataset: $rows rows -> $seed_file"
    
    # Use Python for much faster generation
    python3 -c "
import random
import datetime

random.seed($random_seed)

# Date range: NOW() - 20 days to NOW()
end_date = datetime.datetime.now()
start_date = end_date - datetime.timedelta(days=20)

for i in range($rows):
    # Random timestamp within range
    delta = random.random() * (end_date - start_date).total_seconds()
    ts = start_date + datetime.timedelta(seconds=delta)
    ts_str = ts.strftime('%Y-%m-%d %H:%M:%S')
    
    # Random name (10 uppercase letters)
    name = ''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ', k=10))
    
    # Random data value (0-10000000)
    data = random.randint(0, 10000000)
    
    # Output CSV row
    print(f'{ts_str},{name},{data}')
" > "$seed_file"
    
    log "Seed dataset created: $seed_file ($(wc -l < "$seed_file") rows)"
    
    return 0
}

# Generate seed dataset
log "Starting seed dataset generation"

generate_seed_dataset "$ROWS"

log "Seed dataset generation complete"
log "File created:"
ls -lh "${DATA_DIR}"/events_seed.csv
