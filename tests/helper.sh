# shellcheck shell=bash
#
# helper.sh - Tiny test harness for claude-code-backup.
#
# Each test script sources this, then calls setup_sandbox / assert_* / finish.
# Tests build isolated fake homes and projects under mktemp; they never touch
# the real $HOME and never require a working Claude Code install.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_DIR/bin"
FIXTURES="$REPO_DIR/tests/fixtures"
export CLAUDE_BACKUP_LIB="$REPO_DIR/lib"

_PASS=0
_FAIL=0

# setup_sandbox - create a fresh temp sandbox with home/, project/ and backups/.
# Exports SANDBOX, HOME, PROJECT_DIR, CLAUDE_BACKUP_DIR.
setup_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/ccb-test.XXXXXX")"
  cp -R "$FIXTURES/fake-home" "$SANDBOX/home"
  cp -R "$FIXTURES/fake-project" "$SANDBOX/project"
  export SANDBOX
  export HOME="$SANDBOX/home"
  export PROJECT_DIR="$SANDBOX/project"
  export CLAUDE_BACKUP_DIR="$SANDBOX/backups"
}

teardown_sandbox() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }

# Run a CLI binary from inside the fake project directory.
in_project() { ( cd "$PROJECT_DIR" && "$@" ); }

_ok()   { _PASS=$((_PASS+1)); printf '  ok   - %s\n' "$1"; }
_no()   { _FAIL=$((_FAIL+1)); printf '  FAIL - %s\n' "$1"; }

assert_true()  { if "$@";        then _ok "$ASSERT_MSG"; else _no "$ASSERT_MSG"; fi; }
assert_false() { if "$@";        then _no "$ASSERT_MSG"; else _ok "$ASSERT_MSG"; fi; }
assert_file()  { if [ -f "$1" ]; then _ok "file exists: $1"; else _no "file missing: $1"; fi; }
assert_nofile(){ if [ -f "$1" ]; then _no "file should not exist: $1"; else _ok "absent: $1"; fi; }

# assert_contains <file/string-producer...> - usage: assert_grep <pattern> <file>
assert_grep() {
  if grep -q "$1" "$2" 2>/dev/null; then _ok "matches /$1/: $2"; else _no "no match /$1/: $2"; fi
}

# assert_status <expected> <cmd...> - run cmd, compare exit code.
assert_status() {
  local want="$1"; shift
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then _ok "exit $want: $*"; else _no "exit $got != $want: $*"; fi
}

finish() {
  printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$_PASS" "$_FAIL"
  teardown_sandbox
  [ "$_FAIL" -eq 0 ]
}
