#!/usr/bin/env bash
# Tests for `claude-backup schedule` / `unschedule`.
#
# We never touch the real scheduler: a fake launchctl/systemctl/crontab is put
# first on PATH and HOME points at the sandbox, so plists/units/cron entries
# land inside the sandbox and are torn down with it.
. "$(dirname "$0")/helper.sh"

echo "== test-schedule =="

# --- portable: an invalid --at is rejected --------------------------------
setup_sandbox
ASSERT_MSG="invalid --at time exits non-zero"
assert_status 1 "$BIN/claude-backup" schedule --at 99:99
teardown_sandbox

# --- portable: status with nothing scheduled exits 0 ----------------------
setup_sandbox
ASSERT_MSG="schedule --status exits 0 when nothing is scheduled"
assert_status 0 "$BIN/claude-backup" schedule --status
teardown_sandbox

# --- platform round-trip with fakes ---------------------------------------
setup_sandbox
FAKEBIN="$SANDBOX/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/launchctl"; chmod +x "$FAKEBIN/launchctl"
# Fake crontab backed by a file, for the Linux fallback path.
export CRONFILE="$SANDBOX/cronfile"
cat > "$FAKEBIN/crontab" <<'EOF'
#!/bin/sh
if [ "$1" = "-l" ]; then cat "$CRONFILE" 2>/dev/null; exit 0; fi
cat > "$CRONFILE"; exit 0
EOF
chmod +x "$FAKEBIN/crontab"
# Fake systemctl that reports "no user instance", forcing the cron fallback.
printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/systemctl"; chmod +x "$FAKEBIN/systemctl"

case "$(uname -s)" in
  Darwin)
    PATH="$FAKEBIN:$PATH" "$BIN/claude-backup" schedule --daily --at 03:15 -- --no-history >/dev/null 2>&1
    plist="$HOME/Library/LaunchAgents/com.claude-code-backup.backup.plist"
    assert_file "$plist"
    ASSERT_MSG="plist embeds the scheduled time (Hour 3)"; assert_grep '<integer>3</integer>' "$plist"
    ASSERT_MSG="plist passes through extra opts (--no-history)"; assert_grep 'no-history' "$plist"
    PATH="$FAKEBIN:$PATH" "$BIN/claude-backup" unschedule >/dev/null 2>&1
    ASSERT_MSG="unschedule removes the plist"; assert_nofile "$plist"
    ;;
  Linux)
    PATH="$FAKEBIN:$PATH" "$BIN/claude-backup" schedule --daily --at 03:15 -- --no-history >/dev/null 2>&1
    ASSERT_MSG="crontab gained a claude-code-backup block"
    assert_grep 'claude-code-backup' "$CRONFILE"
    ASSERT_MSG="cron line carries the extra opts"; assert_grep 'no-history' "$CRONFILE"
    PATH="$FAKEBIN:$PATH" "$BIN/claude-backup" unschedule >/dev/null 2>&1
    ASSERT_MSG="unschedule clears the cron block"
    assert_false grep -q 'claude-code-backup' "$CRONFILE"
    ;;
esac
teardown_sandbox

finish
