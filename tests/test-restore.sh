#!/usr/bin/env bash
# Tests for `claude-restore`.
. "$(dirname "$0")/helper.sh"

echo "== test-restore =="

# --- restore puts files back into fake home and project -------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
# wipe config, then restore
rm -rf "$HOME/.claude" "$HOME/.claude.json" "$PROJECT_DIR/.mcp.json" "$PROJECT_DIR/CLAUDE.md"
in_project "$BIN/claude-restore" --force --quiet >/dev/null 2>&1
assert_file "$HOME/.claude.json"
assert_file "$HOME/.claude/settings.json"
assert_file "$PROJECT_DIR/.mcp.json"
assert_file "$PROJECT_DIR/CLAUDE.md"
teardown_sandbox

# --- restore --dry-run does not write files -------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
rm -rf "$HOME/.claude.json" "$PROJECT_DIR/.mcp.json"
in_project "$BIN/claude-restore" --dry-run --force >/dev/null 2>&1
assert_nofile "$HOME/.claude.json"
assert_nofile "$PROJECT_DIR/.mcp.json"
teardown_sandbox

# --- restore takes a pre-restore backup before overwriting ----------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
# leave config in place so there is something to pre-restore
in_project "$BIN/claude-restore" --force --quiet >/dev/null 2>&1
n="$(find "$CLAUDE_BACKUP_DIR/pre-restore" -name 'pre-restore-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')"
ASSERT_MSG="pre-restore backup is created"; assert_true test "$n" -ge "1"
teardown_sandbox

# --- pre-restore backup prunes (symlink+tar, not a full cp -R) ------------
setup_sandbox
mkdir -p "$HOME/.claude/plugins/cache/big"
printf 'BIG\n' > "$HOME/.claude/plugins/cache/big/x"
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
in_project "$BIN/claude-restore" --home-only --force --quiet >/dev/null 2>&1
pre="$(find "$CLAUDE_BACKUP_DIR/pre-restore" -name 'pre-restore-*.tar.gz' | head -n1)"
ASSERT_MSG="pre-restore archive exists"; assert_true test -n "$pre"
ASSERT_MSG="pre-restore prunes plugins/cache (not a raw full copy)"
assert_false grep -q 'plugins/cache/big' <<<"$(tar -tzf "$pre" 2>/dev/null)"
ASSERT_MSG="pre-restore still captures real config (settings.json)"
assert_true grep -q 'home/.claude/settings.json' <<<"$(tar -tzf "$pre" 2>/dev/null)"
teardown_sandbox

# --- restore plan distinguishes overwrite (file) vs merge (dir) -----------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
plan="$(in_project "$BIN/claude-restore" --dry-run 2>&1)"
ASSERT_MSG="plan marks ~/.claude.json as overwrite (single file)"
assert_true grep -Eq 'overwrite:.*/\.claude\.json' <<<"$plan"
ASSERT_MSG="plan marks ~/.claude as merge (directory)"
assert_true grep -Eq 'merge into:.*/\.claude($|[^.])' <<<"$plan"
teardown_sandbox

# --- restore refuses an archive with absolute paths -----------------------
setup_sandbox
payload="$(mktemp -d)"; mkdir -p "$payload/home"; printf 'x\n' > "$payload/home/.claude.json"
mkdir -p "$CLAUDE_BACKUP_DIR"
# -P preserves the leading slash, producing unsafe absolute entries.
tar -czPf "$CLAUDE_BACKUP_DIR/claude-code-backup-0000-evil_h.tar.gz" "$payload/home/.claude.json"
assert_status 1 in_project "$BIN/claude-restore" \
  --from "$CLAUDE_BACKUP_DIR/claude-code-backup-0000-evil_h.tar.gz" --force
rm -rf "$payload"
teardown_sandbox

# --- restore --project-only leaves home untouched -------------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
rm -rf "$HOME/.claude.json" "$PROJECT_DIR/.mcp.json"
in_project "$BIN/claude-restore" --project-only --force --quiet >/dev/null 2>&1
assert_file   "$PROJECT_DIR/.mcp.json"
assert_nofile "$HOME/.claude.json"
teardown_sandbox

finish
