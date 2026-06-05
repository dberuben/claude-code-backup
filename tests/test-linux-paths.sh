#!/usr/bin/env bash
# Path/stat behavior. Runs on any platform; asserts portable expectations.
. "$(dirname "$0")/helper.sh"

echo "== test-linux-paths =="

# --- default backup dir resolves to ~/Backups/claude-code -----------------
setup_sandbox
unset CLAUDE_BACKUP_DIR
out="$(in_project "$BIN/claude-backup" --dry-run 2>&1)"
ASSERT_MSG="default destination is \$HOME/Backups/claude-code"
assert_true grep -q "$HOME/Backups/claude-code" <<<"$out"
export CLAUDE_BACKUP_DIR="$SANDBOX/backups"
teardown_sandbox

# --- \$CLAUDE_BACKUP_DIR override is honored -------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
ASSERT_MSG="archive lands in \$CLAUDE_BACKUP_DIR"
assert_true test -n "$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz')"
teardown_sandbox

# --- portable stat wrappers return numeric values -------------------------
setup_sandbox
probe="$HOME/.claude.json"
mt="$( ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; file_mtime "$probe" ) )"
sz="$( ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; file_size  "$probe" ) )"
ASSERT_MSG="file_mtime returns a number"; assert_true test -n "$mt"
ASSERT_MSG="file_size returns a number";  assert_true test "$sz" -gt 0
teardown_sandbox

# --- list --json emits a directory + backups array ------------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
json="$(in_project "$BIN/claude-backup" list --json 2>/dev/null)"
ASSERT_MSG="list --json includes a directory field"
assert_true grep -q '"directory"' <<<"$json"
ASSERT_MSG="list --json includes a backups array"
assert_true grep -q '"backups"' <<<"$json"
teardown_sandbox

finish
