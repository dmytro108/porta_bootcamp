#!/bin/bash
#
# validate-phase6.sh - Validate Phase 6 implementation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Phase 6 Implementation Validation ==="
echo ""

# Check 1: Directories exist
echo "1. Checking directories..."
for dir in lib data results results/test_runs results/baselines results/comparisons; do
    if [ -d "$SCRIPT_DIR/$dir" ]; then
        echo "   ✓ $dir exists"
    else
        echo "   ✗ $dir missing"
        exit 1
    fi
done
echo ""

# Check 2: Scripts exist and are executable
echo "2. Checking scripts..."
for script in test-cleanup-methods.sh lib/test-utils.sh lib/test-scenarios.sh generate-seeds.sh; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        echo "   ✓ $script exists and is executable"
    else
        echo "   ✗ $script missing or not executable"
        exit 1
    fi
done
echo ""

# Check 3: Seed datasets exist
echo "3. Checking seed datasets..."
for seed in data/events_seed_10k_v1.0.csv data/events_seed_100k_v1.0.csv; do
    if [ -f "$SCRIPT_DIR/$seed" ]; then
        rows=$(wc -l < "$SCRIPT_DIR/$seed")
        echo "   ✓ $seed exists ($rows rows)"
    else
        echo "   ✗ $seed missing"
        exit 1
    fi
    
    # Check MD5
    if [ -f "$SCRIPT_DIR/$seed.md5" ]; then
        echo "   ✓ $seed.md5 exists"
    else
        echo "   ✗ $seed.md5 missing"
    fi
done
echo ""

# Check 4: db-cleanup.sh has all methods
echo "4. Checking cleanup methods..."
for method in execute_truncate_cleanup execute_partition_drop_cleanup execute_copy_cleanup execute_batch_delete_cleanup; do
    if grep -q "$method" "$SCRIPT_DIR/db-cleanup.sh"; then
        echo "   ✓ $method implemented"
    else
        echo "   ✗ $method not found"
        exit 1
    fi
done
echo ""

# Check 5: Test --dry-run works
echo "5. Testing dry-run mode..."
if "$SCRIPT_DIR/test-cleanup-methods.sh" --scenario basic --dry-run >/dev/null 2>&1; then
    echo "   ✓ Dry-run mode works"
else
    echo "   ✗ Dry-run mode failed"
    exit 1
fi
echo ""

echo "=== Phase 6 Implementation Validation: PASSED ==="
echo ""
echo "Next steps:"
echo "1. Review implementation files"
echo "2. Test individual scenarios manually"
echo "3. Update documentation"
