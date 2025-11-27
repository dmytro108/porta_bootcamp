#!/bin/bash
#
# test-cleanup-methods.sh - Master test orchestration for cleanup methods
#
# Usage:
#   ./test-cleanup-methods.sh --scenario <name> [options]
#
# Scenarios:
#   basic           - Test all methods with 10K rows, no concurrent load
#   concurrent      - Test all methods with 10K rows + concurrent load
#   performance     - Performance benchmark with 100K rows
#   stress          - Stress test with 1M rows (optional)
#   single          - Test single method
#   all             - Run all scenarios (basic, concurrent, performance)

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment from task01
if [ -f "${SCRIPT_DIR}/../task01/task01.env.sh" ]; then
    source "${SCRIPT_DIR}/../task01/task01.env.sh"
fi

# Configuration
RESULTS_DIR="${SCRIPT_DIR}/results"
DATA_DIR="${SCRIPT_DIR}/data"
DB_NAME="cleanup_bench"

# Source libraries
source "${SCRIPT_DIR}/lib/test-utils.sh"
source "${SCRIPT_DIR}/lib/test-scenarios.sh"

# Default values
SCENARIO=""
METHOD=""
DATASET_SIZE="10000"
CONCURRENT_LOAD=false
TRAFFIC_RATE=10
DRY_RUN=false
VERBOSE=false

# MySQL configuration
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"

#############################################################################
# Logging Functions
#############################################################################

log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*"
    fi
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

#############################################################################
# Argument Parsing
#############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scenario)
                SCENARIO="$2"
                shift 2
                ;;
            --method)
                METHOD="$2"
                shift 2
                ;;
            --size)
                DATASET_SIZE="$2"
                shift 2
                ;;
            --concurrent)
                CONCURRENT_LOAD=true
                shift
                ;;
            --traffic-rate)
                TRAFFIC_RATE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat <<EOF
Usage: test-cleanup-methods.sh [options]

Test Scenarios:
  --scenario basic          Test all methods with 10K rows (default)
  --scenario concurrent     Test all methods with concurrent load
  --scenario performance    Performance benchmark with 100K rows
  --scenario stress         Stress test with 1M rows
  --scenario single         Test single method (requires --method)
  --scenario all            Run all scenarios

Options:
  --method <name>           Test specific method (partition_drop|truncate|copy|batch_delete)
  --size <rows>             Dataset size (default: 10000)
  --concurrent              Enable concurrent load during test
  --traffic-rate <ops/sec>  Traffic rate for concurrent load (default: 10)
  --dry-run                 Preview test plan without execution
  --verbose                 Enable detailed logging
  -h, --help                Show this help message

Examples:
  # Run basic test suite
  ./test-cleanup-methods.sh --scenario basic

  # Test all methods with concurrent load
  ./test-cleanup-methods.sh --scenario concurrent

  # Performance benchmark
  ./test-cleanup-methods.sh --scenario performance

  # Test single method
  ./test-cleanup-methods.sh --scenario single --method batch_delete

  # Custom test with concurrent load
  ./test-cleanup-methods.sh --method partition_drop --size 50000 --concurrent
EOF
}

#############################################################################
# Main Function
#############################################################################

main() {
    parse_arguments "$@"
    
    # Default scenario
    if [ -z "$SCENARIO" ]; then
        if [ -n "$METHOD" ]; then
            SCENARIO="single"
        else
            SCENARIO="basic"
        fi
    fi
    
    log "INFO" "=== Cleanup Methods Test Suite ==="
    log "INFO" "Scenario: ${SCENARIO}"
    log "INFO" "Dataset size: ${DATASET_SIZE} rows"
    log "INFO" "Concurrent load: ${CONCURRENT_LOAD}"
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No actual execution"
        log "INFO" "Would execute scenario: ${SCENARIO}"
        
        case "$SCENARIO" in
            basic)
                log "INFO" "Would test all 4 methods with 10K rows, no concurrent load"
                ;;
            concurrent)
                log "INFO" "Would test all 4 methods with ${DATASET_SIZE} rows and ${TRAFFIC_RATE} ops/sec traffic"
                ;;
            performance)
                log "INFO" "Would benchmark all 4 methods with 100K rows"
                ;;
            single)
                log "INFO" "Would test method: ${METHOD} with ${DATASET_SIZE} rows"
                ;;
            all)
                log "INFO" "Would run: basic, concurrent, and performance scenarios"
                ;;
        esac
        
        exit 0
    fi
    
    # Initialize test environment
    initialize_test_environment
    
    # Execute scenario
    case "$SCENARIO" in
        basic)
            run_basic_test_suite
            ;;
        concurrent)
            run_concurrent_test_suite
            ;;
        performance)
            run_performance_benchmark
            ;;
        stress)
            log "ERROR" "Stress test not yet implemented"
            exit 1
            ;;
        single)
            if [ -z "$METHOD" ]; then
                log "ERROR" "Method must be specified for single scenario"
                show_usage
                exit 1
            fi
            run_single_method_test "$METHOD"
            ;;
        all)
            run_all_scenarios
            ;;
        *)
            log "ERROR" "Unknown scenario: $SCENARIO"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate summary report
    generate_test_summary_report
    
    log "INFO" "Test suite completed successfully"
}

main "$@"
