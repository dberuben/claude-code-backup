#!/usr/bin/env bash
# Tests for `claude-backup`.
. "$(dirname "$0")/helper.sh"

echo "== test-backup =="

# --- backup creates an archive containing a manifest ----------------------
setup_sandbox
in_project "$BIN/claude-backup" --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
ASSERT_MSG="backup created an archive"; assert_true test -n "$archive"

contents="$(tar -tzf "$archive" 2>/dev/null)"
ASSERT_MSG="archive contains manifest.txt";        assert_true grep -q 'manifest.txt' <<<"$contents"
ASSERT_MSG="archive contains home/.claude/settings.json"; assert_true grep -q 'home/.claude/settings.json' <<<"$contents"
ASSERT_MSG="archive contains home/.claude.json";   assert_true grep -q 'home/.claude.json' <<<"$contents"
ASSERT_MSG="archive contains project/.mcp.json";   assert_true grep -q 'project/.mcp.json' <<<"$contents"

# manifest content sanity
tmpx="$(mktemp -d)"; tar -xzf "$archive" -C "$tmpx" manifest.txt ./manifest.txt 2>/dev/null
assert_grep "backup_tool_version" "$tmpx/manifest.txt"
assert_grep "platform:"           "$tmpx/manifest.txt"
rm -rf "$tmpx"
teardown_sandbox

# --- --no-project excludes project files ----------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
contents="$(tar -tzf "$archive" 2>/dev/null)"
ASSERT_MSG="--no-project excludes project/.mcp.json"
assert_false grep -q 'project/.mcp.json' <<<"$contents"
ASSERT_MSG="--no-project still includes home config"
assert_true grep -q 'home/.claude.json' <<<"$contents"
teardown_sandbox

# --- --dry-run does not create an archive ---------------------------------
setup_sandbox
in_project "$BIN/claude-backup" --dry-run --quiet >/dev/null 2>&1
n="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')"
ASSERT_MSG="--dry-run writes no archive"; assert_true test "$n" = "0"
teardown_sandbox

# --- pruning: drop bulky/ephemeral dirs at any depth, keep manifests ------
setup_sandbox
# bulky/ephemeral entries (incl. one nested deep) + a small plugin manifest
mkdir -p "$HOME/.claude/plugins/cache/big" \
         "$HOME/.claude/security/venv/lib/py/site-packages" \
         "$HOME/.claude/telemetry"
printf 'BIG\n'         > "$HOME/.claude/plugins/cache/big/x"
printf 'SO\n'          > "$HOME/.claude/security/venv/lib/py/site-packages/lib.so"
printf 't\n'           > "$HOME/.claude/telemetry/t"
printf '{"i":["a"]}\n' > "$HOME/.claude/plugins/installed_plugins.json"
in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
contents="$(tar -tzf "$archive" 2>/dev/null)"
ASSERT_MSG="prunes plugins/cache";              assert_false grep -q 'plugins/cache/' <<<"$contents"
ASSERT_MSG="prunes deeply-nested site-packages"; assert_false grep -q 'site-packages' <<<"$contents"
ASSERT_MSG="prunes telemetry";                  assert_false grep -q '/telemetry/' <<<"$contents"
ASSERT_MSG="keeps installed_plugins.json manifest"
assert_true grep -q 'plugins/installed_plugins.json' <<<"$contents"
teardown_sandbox

# --- --full keeps everything (no pruning) ---------------------------------
setup_sandbox
mkdir -p "$HOME/.claude/plugins/cache"
printf 'B\n' > "$HOME/.claude/plugins/cache/x"
in_project "$BIN/claude-backup" --no-project --full --quiet >/dev/null 2>&1
archive="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
ASSERT_MSG="--full keeps plugins/cache"
assert_true grep -q 'plugins/cache/x' <<<"$(tar -tzf "$archive" 2>/dev/null)"
teardown_sandbox

# --- strict secrets aborts when a (realistic) secret is present -----------
setup_sandbox
# A realistic-length key; the tightened scanner ignores short fake tokens.
printf '{"ANTHROPIC_API_KEY":"sk-ant-api03-AbCdEf0123456789ghIjkl"}\n' > "$HOME/.claude.json"
assert_status 1 in_project "$BIN/claude-backup" --strict-secrets --no-project
teardown_sandbox

finish
