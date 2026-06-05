#!/usr/bin/env bash
# Portability / edge-case regression tests:
#   - empty arrays under `set -u` (the bash 3.2 "unbound variable" trap)
#   - graceful failure when there is no config to back up
#   - tightened secret scanner (fewer false positives, still catches real keys)
. "$(dirname "$0")/helper.sh"

echo "== test-compat =="

# --- --full (empty exclude array) must not crash --------------------------
setup_sandbox
ASSERT_MSG="--full backup succeeds (no empty-array crash)"
assert_status 0 in_project "$BIN/claude-backup" --no-project --full --quiet
teardown_sandbox

# --- the same, explicitly under /bin/bash if it is 3.2 --------------------
if [ -x /bin/bash ]; then
  sysbash_ver="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null)"
  case "$sysbash_ver" in
    3.*)
      setup_sandbox
      out="$(in_project env CLAUDE_BACKUP_LIB="$REPO_DIR/lib" \
             /bin/bash "$BIN/claude-backup" --no-project --full --quiet 2>&1)"
      ASSERT_MSG="--full runs under /bin/bash $sysbash_ver without 'unbound variable'"
      assert_false grep -qi 'unbound variable' <<<"$out"
      # banner with everything disabled => empty parts array
      printf 'BANNER_SHOW_GIT=false\nBANNER_SHOW_ENV=false\nBANNER_SHOW_BACKUP_STATUS=false\nBANNER_SHOW_MCP_STATUS=false\nBANNER_SHOW_SECRET_WARNING=false\n' \
        > "$SANDBOX/banner.conf"
      bout="$(in_project env CLAUDE_BACKUP_LIB="$REPO_DIR/lib" CCB_BANNER_CONF="$SANDBOX/banner.conf" \
             /bin/bash "$BIN/claude-backup-banner" 2>&1)"
      ASSERT_MSG="banner (empty parts) runs under /bin/bash $sysbash_ver without crash"
      assert_false grep -qi 'unbound variable' <<<"$bout"
      teardown_sandbox
      ;;
    *) echo "  (skip) /bin/bash is $sysbash_ver, not 3.x" ;;
  esac
else
  echo "  (skip) no /bin/bash"
fi

# --- no config at all => clean failure, not a crash -----------------------
setup_sandbox
rm -rf "$HOME/.claude" "$HOME/.claude.json"
out="$(in_project "$BIN/claude-backup" --no-project 2>&1)"; rc=$?
ASSERT_MSG="empty-config backup exits non-zero"; assert_true test "$rc" -ne 0
ASSERT_MSG="empty-config backup reports 'nothing to back up' (no unbound-variable)"
assert_true grep -qi 'nothing to back up' <<<"$out"
teardown_sandbox

# --- secret scanner: catches real keys, ignores prose ---------------------
scanf() { ( export CCB_LIB_DIR="$REPO_DIR/lib"; . "$CCB_LIB_DIR/common.sh"; scan_file "$1" ); }
work="$(mktemp -d)"
printf 'sk-ant-abcdefgh01234567 ZZ\n'        > "$work/key.txt"
printf '{"token": "xoxb-1234567890-abcd"}\n' > "$work/assign.json"
printf 'api_key = "ABCDEFGH12345678"\n'      > "$work/env.conf"
printf 'This skill explains how a token works; the secret to success.\n' > "$work/prose.md"
printf 'Use your password to log in. Authorization required.\n'          > "$work/prose2.md"
ASSERT_MSG="detects sk-ant- key";              assert_true  scanf "$work/key.txt"
ASSERT_MSG="detects assigned slack token";     assert_true  scanf "$work/assign.json"
ASSERT_MSG="detects api_key = value";          assert_true  scanf "$work/env.conf"
ASSERT_MSG="ignores the word 'token'/'secret' in prose"; assert_false scanf "$work/prose.md"
ASSERT_MSG="ignores 'password'/'authorization' in prose"; assert_false scanf "$work/prose2.md"
rm -rf "$work"

finish
