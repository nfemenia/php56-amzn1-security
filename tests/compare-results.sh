#!/bin/bash
# Compare a run-tests.php summary file against a list of tests allowed to fail.
# Usage: compare-results.sh <test-results.txt> <expected-failures.txt>
# Exits 1 if any test failed that is not in the expected list.
set -euo pipefail
RESULTS="$1"
EXPECTED="$2"

failed=$(awk '/^FAILED TEST SUMMARY/{f=1; next} f && /^=+$/{exit} f && /^-+$/{next} f' "$RESULTS" \
  | grep -o '\[[^]]*\]$' | tr -d '[]' | sort -u || true)
expected=$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$EXPECTED" | grep -v '^$' | sort -u)
flaky=$(grep '# flaky' "$EXPECTED" | sed -e 's/[[:space:]]*#.*//' | sort -u || true)

grep -E '^(Number of tests|Tests (failed|passed|skipped))' "$RESULTS" || true

unexpected=$(comm -23 <(echo "$failed" | grep -v '^$' || true) <(echo "$expected"))
now_passing=$(comm -13 <(echo "$failed") <(echo "$expected") | grep -vxF -f <(echo "$flaky") | grep -v '^$' || true)

if [ -n "$now_passing" ]; then
  echo "Expected to fail but passed (consider removing from $EXPECTED):"
  echo "$now_passing" | sed 's/^/  /'
fi
if [ -n "$unexpected" ]; then
  echo "UNEXPECTED FAILURES:"
  echo "$unexpected" | sed 's/^/  /'
  exit 1
fi
echo "Test results match $EXPECTED"
