#!/usr/bin/env bash
# Platform behavior. Runs on any platform; asserts portable expectations and
# that the BSD/GNU `stat` wrappers in lib/platform.sh work on this host.
. "$(dirname "$0")/helper.sh"

echo "== test-macos-paths =="

platform="$(uname -s)"

# --- a plain backup succeeds on this platform -----------------------------
setup_sandbox
ASSERT_MSG="backup succeeds (exit 0) on $platform"
assert_status 0 in_project "$BIN/claude-backup" --no-project --quiet
ASSERT_MSG="backup produced a local archive"
assert_true test -n "$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz')"
teardown_sandbox

# --- platform detection resolves to a supported OS ------------------------
setup_sandbox
plat="$( ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; printf '%s' "$CCB_PLATFORM" ) )"
ASSERT_MSG="detect_platform yields macos or linux on this host"
assert_true test "$plat" = "macos" -o "$plat" = "linux"
teardown_sandbox

# --- portable stat wrappers agree with the platform -----------------------
setup_sandbox
probe="$HOME/.claude.json"
sz="$( ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; file_size  "$probe" ) )"
mt="$( ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; file_mtime "$probe" ) )"
ASSERT_MSG="file_size is a positive number on $platform"; assert_true test "$sz" -gt 0
ASSERT_MSG="file_mtime is non-empty on $platform";        assert_true test -n "$mt"
teardown_sandbox

finish
