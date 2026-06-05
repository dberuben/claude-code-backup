#!/usr/bin/env bash
# Tests for the banner and doctor (which must run without Claude Code).
. "$(dirname "$0")/helper.sh"

echo "== test-banner =="

# --- banner warns when no backup exists -----------------------------------
setup_sandbox
out="$(in_project env NO_COLOR=1 "$BIN/claude-backup-banner" 2>&1)"
ASSERT_MSG="banner shows 'never' when no backup exists"
assert_true grep -q 'backup: never' <<<"$out"
ASSERT_MSG="banner shows mcp status"
assert_true grep -q 'mcp:' <<<"$out"
teardown_sandbox

# --- banner shows a recent backup age after a backup ----------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
out="$(in_project env NO_COLOR=1 "$BIN/claude-backup-banner" 2>&1)"
ASSERT_MSG="banner shows an 'ago' age after backup"
assert_true grep -q 'ago' <<<"$out"
ASSERT_MSG="banner reports mcp: ok when .mcp.json present"
assert_true grep -q 'mcp: ok' <<<"$out"
teardown_sandbox

# --- banner respects BANNER_ENABLED=false ---------------------------------
setup_sandbox
mkdir -p "$HOME/.claude-backup"
printf 'BANNER_ENABLED=false\n' > "$HOME/.claude-backup/banner.conf"
out="$(in_project env CCB_BANNER_CONF="$HOME/.claude-backup/banner.conf" "$BIN/claude-backup-banner" 2>&1)"
ASSERT_MSG="disabled banner prints nothing"
assert_true test -z "$out"
teardown_sandbox

# --- doctor runs without Claude Code installed ----------------------------
setup_sandbox
# Force a PATH without `claude` so doctor must handle its absence.
out="$(in_project env PATH="/usr/bin:/bin" NO_COLOR=1 "$BIN/claude-backup" doctor 2>&1)"
ASSERT_MSG="doctor exits cleanly without claude"
assert_status 0 in_project env PATH="/usr/bin:/bin" "$BIN/claude-backup" doctor
ASSERT_MSG="doctor reports missing Claude Code as a warning, not a failure"
assert_true grep -q 'Claude Code binary not found' <<<"$out"
teardown_sandbox

finish
