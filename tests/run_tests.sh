#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running unit tests..."
echo ""

FAILED=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ "$(basename "$test_file")" == "test_helpers.sh" ]] && continue
    echo "--- $(basename "$test_file") ---"
    if bash "$test_file"; then
        echo "  All tests passed."
    else
        echo "  SOME TESTS FAILED."
        FAILED=1
    fi
    echo ""
done

if [[ $FAILED -eq 1 ]]; then
    echo "RESULT: Some tests failed."
    exit 1
else
    echo "RESULT: All tests passed."
fi
