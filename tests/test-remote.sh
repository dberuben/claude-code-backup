#!/usr/bin/env bash
# Tests for the custom-command remote (`--remote cmd:…` and `push`).
. "$(dirname "$0")/helper.sh"

echo "== test-remote =="

# --- --remote during backup runs the command with {} substitution --------
setup_sandbox
mkdir -p "$SANDBOX/remote"
in_project "$BIN/claude-backup" --no-project --quiet \
  --remote "cmd:cp {} $SANDBOX/remote/" >/dev/null 2>&1
n="$(find "$SANDBOX/remote" -name 'claude-code-backup-*.tar.gz' | wc -l | tr -d ' ')"
ASSERT_MSG="--remote pushed the archive to the remote dir"; assert_true test "$n" = "1"
ns="$(find "$SANDBOX/remote" -name '*.sha256' | wc -l | tr -d ' ')"
ASSERT_MSG="--remote also pushed the .sha256 sidecar"; assert_true test "$ns" = "1"
teardown_sandbox

# --- append mode: no {} means the path is appended as last arg ------------
setup_sandbox
mkdir -p "$SANDBOX/remote"
in_project "$BIN/claude-backup" --no-project --quiet \
  --remote "cmd:cp -t $SANDBOX/remote" >/dev/null 2>&1 || true
# `cp -t` is GNU-only; on BSD this push fails but must NOT delete the local backup.
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
ASSERT_MSG="a failed remote push keeps the local backup"; assert_true test -n "$archive"
teardown_sandbox

# --- `push` of an existing archive ----------------------------------------
setup_sandbox
mkdir -p "$SANDBOX/remote"
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
"$BIN/claude-backup" push --from "$archive" --remote "cmd:cp {} $SANDBOX/remote/" >/dev/null 2>&1
ASSERT_MSG="push copied the chosen archive"
assert_file "$SANDBOX/remote/$(basename "$archive")"

# --- push with no remote configured fails ---------------------------------
ASSERT_MSG="push without a remote exits non-zero"
assert_status 1 env -u CLAUDE_BACKUP_REMOTE "$BIN/claude-backup" push --from "$archive"
teardown_sandbox

# --- a path containing $(…) is treated as data, not code (no injection) ----
setup_sandbox
export CCB_LIB_DIR="$CLAUDE_BACKUP_LIB"
. "$CLAUDE_BACKUP_LIB/platform.sh"; detect_platform
. "$CLAUDE_BACKUP_LIB/common.sh"
rm -f "$SANDBOX/PWNED"
ccb_push_remote "$SANDBOX/arch_\$(touch $SANDBOX/PWNED).tar.gz" "cmd:echo {}" >/dev/null 2>&1 || true
ASSERT_MSG="command substitution in the archive path is NOT executed"
assert_nofile "$SANDBOX/PWNED"
teardown_sandbox

# --- CLAUDE_BACKUP_REMOTE env var is honoured -----------------------------
setup_sandbox
mkdir -p "$SANDBOX/remote"
CLAUDE_BACKUP_REMOTE="cmd:cp {} $SANDBOX/remote/" \
  in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
n="$(find "$SANDBOX/remote" -name 'claude-code-backup-*.tar.gz' | wc -l | tr -d ' ')"
ASSERT_MSG="CLAUDE_BACKUP_REMOTE triggers a push"; assert_true test "$n" = "1"
teardown_sandbox

finish
