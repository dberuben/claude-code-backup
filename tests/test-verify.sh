#!/usr/bin/env bash
# Tests for `claude-backup verify` and the .sha256 sidecar.
. "$(dirname "$0")/helper.sh"

echo "== test-verify =="

# --- a backup writes a .sha256 sidecar ------------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
ASSERT_MSG="backup created an archive"; assert_true test -n "$archive"
assert_file "$archive.sha256"
ASSERT_MSG="sidecar names the archive"
assert_grep "$(basename "$archive")" "$archive.sha256"

# --- verify passes on a good archive --------------------------------------
ASSERT_MSG="verify exits 0 on a valid archive"
assert_status 0 "$BIN/claude-backup" verify --from "$archive"

# --- verify --json reports ok ---------------------------------------------
out="$("$BIN/claude-backup" verify --from "$archive" --json 2>/dev/null)"
ASSERT_MSG="verify --json says status ok"
assert_true grep -q '"status":"ok"' <<<"$out"
ASSERT_MSG="verify --json says checksum ok"
assert_true grep -q '"checksum":"ok"' <<<"$out"
teardown_sandbox

# --- verify fails on a corrupted archive ----------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
printf 'CORRUPTION' >> "$archive"     # break the gzip stream
ASSERT_MSG="verify exits non-zero on a corrupted archive"
assert_status 1 "$BIN/claude-backup" verify --from "$archive"
teardown_sandbox

# --- verify detects a checksum mismatch (archive changed, sidecar stale) ---
setup_sandbox
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
# Replace the archive with a different-but-valid gzip; sidecar now mismatches.
printf 'different' | gzip -c > "$archive"
ASSERT_MSG="verify exits non-zero on a checksum mismatch"
assert_status 1 "$BIN/claude-backup" verify --from "$archive"
teardown_sandbox

finish
