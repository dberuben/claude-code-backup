#!/usr/bin/env bash
# Tests for selective restore (`--only`) and `--list-contents`.
. "$(dirname "$0")/helper.sh"

echo "== test-restore-selective =="

# Build an archive whose home config has agents + commands.
make_archive() {
  setup_sandbox
  mkdir -p "$HOME/.claude/agents" "$HOME/.claude/commands"
  printf 'AGENT\n'   > "$HOME/.claude/agents/a.md"
  printf 'COMMAND\n' > "$HOME/.claude/commands/c.md"
  in_project "$BIN/claude-backup" --no-project --quiet >/dev/null 2>&1
  ARCHIVE="$(find "$CLAUDE_BACKUP_DIR" -name 'claude-code-backup-*.tar.gz' | head -n1)"
}

# --- --list-contents reports the categories present -----------------------
make_archive
out="$("$BIN/claude-restore" --list-contents --from "$ARCHIVE" 2>&1)"
ASSERT_MSG="--list-contents shows agents present"; assert_true grep -q 'agents:.*agents' <<<"$out"
ASSERT_MSG="--list-contents shows commands present"; assert_true grep -q 'commands:.*commands' <<<"$out"
ASSERT_MSG="--list-contents shows skills absent"; assert_true grep -q 'skills: (absent)' <<<"$out"
teardown_sandbox

# --- --only agents,commands restores just those, not history --------------
make_archive
rm -rf "$HOME/.claude/agents" "$HOME/.claude/commands"
"$BIN/claude-restore" --only agents,commands --from "$ARCHIVE" \
  --home-only --force --no-backup-existing >/dev/null 2>&1
assert_file "$HOME/.claude/agents/a.md"
assert_file "$HOME/.claude/commands/c.md"
ASSERT_MSG="history was NOT restored (not requested)"
assert_nofile "$HOME/.claude/projects/marker"
teardown_sandbox

# --- an unknown category is rejected --------------------------------------
make_archive
ASSERT_MSG="unknown category exits non-zero"
assert_status 1 "$BIN/claude-restore" --only nonsense --from "$ARCHIVE" --force
teardown_sandbox

# --- --only with a dry-run writes nothing ---------------------------------
make_archive
rm -rf "$HOME/.claude/agents"
"$BIN/claude-restore" --only agents --from "$ARCHIVE" --home-only --dry-run --force >/dev/null 2>&1
ASSERT_MSG="--dry-run with --only restores nothing"
assert_nofile "$HOME/.claude/agents/a.md"
teardown_sandbox

finish
