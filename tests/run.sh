#!/usr/bin/env bash
# Run the whole claude-code-backup test suite. Exits non-zero if any test fails.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

for t in test-backup.sh test-restore.sh test-linux-paths.sh test-macos-paths.sh test-banner.sh test-compat.sh; do
  echo "-------------------------------------------------------------------"
  bash "$DIR/$t" || fail=1
done

echo "==================================================================="
if [ "$fail" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "SOME SUITES FAILED"
fi
exit "$fail"
