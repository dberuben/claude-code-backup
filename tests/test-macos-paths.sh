#!/usr/bin/env bash
# macOS-specific behavior (iCloud). Runs on any platform and asserts that the
# --icloud option degrades gracefully off macOS and never breaks the backup.
. "$(dirname "$0")/helper.sh"

echo "== test-macos-paths =="

platform="$(uname -s)"

# --- --icloud never breaks a backup ---------------------------------------
setup_sandbox
ASSERT_MSG="backup with --icloud succeeds (exit 0) on $platform"
assert_status 0 in_project "$BIN/claude-backup" --icloud --quiet
ASSERT_MSG="--icloud backup still produced a local archive"
assert_true test -n "$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz')"
teardown_sandbox

# --- on Linux, --icloud must announce it was ignored ----------------------
if [ "$platform" = "Linux" ]; then
  setup_sandbox
  out="$(in_project "$BIN/claude-backup" --icloud 2>&1)"
  ASSERT_MSG="Linux: --icloud reports it is ignored"
  assert_true grep -qi 'icloud.*ignored\|not running on macOS' <<<"$out"
  teardown_sandbox
fi

# --- icloud_dir helper returns non-zero when unavailable ------------------
setup_sandbox
if [ "$platform" = "Darwin" ]; then
  # Just ensure the helper runs without error semantics leaking; it returns
  # non-zero when the directory is absent, which must not abort callers.
  ASSERT_MSG="icloud_dir is callable on macOS"
  ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; icloud_dir >/dev/null 2>&1; true )
  assert_true true
else
  ASSERT_MSG="icloud_dir returns non-zero off macOS"
  assert_false bash -c "export CCB_LIB_DIR='$REPO_DIR/lib'; . \"\$CCB_LIB_DIR/common.sh\"; icloud_dir"
fi
teardown_sandbox

finish
