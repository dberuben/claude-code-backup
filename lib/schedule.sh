# shellcheck shell=bash
#
# schedule.sh - Install/remove a recurring backup using the OS scheduler.
#
#   macOS  -> launchd user agent  (~/Library/LaunchAgents)
#   Linux  -> systemd user timer  (~/.config/systemd/user), else crontab
#
# The scheduled job runs a global backup (--no-project: a daemon has no
# meaningful working directory). Extra options after `--` are appended verbatim,
# so a remote push or --no-history can be scheduled too.
#
# Sourced by bin/claude-backup for the `schedule` / `unschedule` subcommands.

CCB_SCHED_LABEL="com.claude-code-backup.backup"   # launchd label / systemd unit base
CCB_SCHED_UNIT="claude-code-backup"               # systemd unit name (.service/.timer)
CCB_SCHED_CONF_DIR="$HOME/.claude-backup"
CCB_SCHED_LOG="$CCB_SCHED_CONF_DIR/schedule.log"
CCB_CRON_BEGIN="# >>> claude-code-backup >>>"
CCB_CRON_END="# <<< claude-code-backup <<<"

# --- small quoting helpers -------------------------------------------------
# ccb_shquote <s> - single-quote a string for a POSIX shell / crontab line.
ccb_shquote() { local s="$1"; printf "'%s'" "${s//\'/\'\\\'\'}"; }
# ccb_sdquote <s> - double-quote a string for a systemd ExecStart= value.
ccb_sdquote() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }

# ccb_sched_usage - help for the schedule subcommand.
ccb_sched_usage() {
  cat <<'EOF'
claude-backup schedule - install a recurring backup

USAGE:
  claude-backup schedule [--daily|--weekly|--hourly] [--at HH:MM] [--dest DIR] [-- <backup opts>]
  claude-backup schedule --status
  claude-backup unschedule

  Default interval is --daily at 02:00. Anything after `--` is passed to each
  backup, e.g.:  schedule --daily --at 02:30 -- --no-history --remote 'cmd:rclone copy {} d:/'
EOF
}

# do_schedule [args] - parse options and install the recurring job.
do_schedule() {
  local interval="daily" at="" dest="" want_status=0
  local extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --daily)  interval="daily" ;;
      --weekly) interval="weekly" ;;
      --hourly) interval="hourly" ;;
      --at)     at="${2:-}"; shift ;;
      --dest)   dest="${2:-}"; shift ;;
      --status) want_status=1 ;;
      --)       shift; while [ $# -gt 0 ]; do extra+=("$1"); shift; done; break ;;
      -h|--help) ccb_sched_usage; return 0 ;;
      *) die "unknown schedule option: $1 (see 'claude-backup schedule --help')" ;;
    esac
    shift
  done

  [ "$want_status" = "1" ] && { ccb_sched_status; return $?; }

  # Parse --at HH:MM into zero-padded hour/minute.
  local hh="02" mm="00"
  if [ -n "$at" ]; then
    case "$at" in
      [0-9]:[0-9][0-9])       hh="0${at%%:*}"; mm="${at##*:}" ;;
      [0-9][0-9]:[0-9][0-9])  hh="${at%%:*}";  mm="${at##*:}" ;;
      *) die "invalid --at time, expected HH:MM: $at" ;;
    esac
    [ "$hh" -le 23 ] 2>/dev/null && [ "$mm" -le 59 ] 2>/dev/null \
      || die "invalid --at time, hour 00-23 minute 00-59: $at"
  fi

  # Resolve the backup binary and assemble its argument list.
  local bin="${CCB_SELF_BIN:-}"
  [ -n "$bin" ] && [ -x "$bin" ] || bin="$(command -v claude-backup 2>/dev/null || echo claude-backup)"
  local args=(--quiet --no-project)
  [ -n "$dest" ] && args+=(--dest "$dest")
  args+=(${extra[@]+"${extra[@]}"})

  # Refuse newlines in any scheduled argument: a newline would terminate an
  # ExecStart= line (systemd) or a crontab line and let extra directives/jobs be
  # injected. Normal options never contain newlines, so this only blocks abuse.
  local _a _nl
  _nl=$'\n'
  for _a in "${args[@]}"; do
    case "$_a" in
      *"$_nl"*) die "scheduled arguments must not contain newlines" ;;
    esac
  done

  mkdir -p "$CCB_SCHED_CONF_DIR" 2>/dev/null || true

  case "$CCB_PLATFORM" in
    macos) ccb_sched_launchd "$interval" "$hh" "$mm" "$bin" "${args[@]}" ;;
    linux)
      if ccb_systemd_available; then
        ccb_sched_systemd "$interval" "$hh" "$mm" "$bin" "${args[@]}"
      else
        log_info "systemd user instance not available; using crontab."
        ccb_sched_cron "$interval" "$hh" "$mm" "$bin" "${args[@]}"
      fi ;;
    *) die "scheduling is not supported on this platform ($(uname -s))" ;;
  esac
}

# do_unschedule [args] - remove whatever recurring job we installed.
do_unschedule() {
  case "$CCB_PLATFORM" in
    macos) ccb_unsched_launchd ;;
    linux) ccb_systemd_available && ccb_unsched_systemd; ccb_unsched_cron ;;
    *)     die "scheduling is not supported on this platform ($(uname -s))" ;;
  esac
}

# ---------------------------------------------------------------------------
# macOS: launchd
# ---------------------------------------------------------------------------
ccb_launchd_plist() { printf '%s/Library/LaunchAgents/%s.plist\n' "$HOME" "$CCB_SCHED_LABEL"; }

# ccb_sched_launchd <interval> <hh> <mm> <bin> <args...>
ccb_sched_launchd() {
  local interval="$1" hh="$2" mm="$3"; shift 3
  local plist; plist="$(ccb_launchd_plist)"
  mkdir -p "$(dirname "$plist")" || die "cannot create LaunchAgents dir"

  # Calendar dict varies by interval (launchd fires hourly when only Minute is set).
  local cal=""
  case "$interval" in
    hourly) cal="    <key>Minute</key><integer>$((10#$mm))</integer>" ;;
    daily)  cal="    <key>Hour</key><integer>$((10#$hh))</integer>
    <key>Minute</key><integer>$((10#$mm))</integer>" ;;
    weekly) cal="    <key>Weekday</key><integer>0</integer>
    <key>Hour</key><integer>$((10#$hh))</integer>
    <key>Minute</key><integer>$((10#$mm))</integer>" ;;
  esac

  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    printf '  <key>Label</key><string>%s</string>\n' "$CCB_SCHED_LABEL"
    printf '  <key>ProgramArguments</key>\n  <array>\n'
    printf '    <string>/bin/bash</string>\n'
    local a
    for a in "$@"; do printf '    <string>%s</string>\n' "$(ccb_xml_escape "$a")"; done
    printf '  </array>\n'
    printf '  <key>StartCalendarInterval</key>\n  <dict>\n%s\n  </dict>\n' "$cal"
    printf '  <key>StandardOutPath</key><string>%s</string>\n' "$CCB_SCHED_LOG"
    printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$CCB_SCHED_LOG"
    printf '</dict>\n</plist>\n'
  } >"$plist" || die "cannot write plist: $plist"

  if command -v launchctl >/dev/null 2>&1; then
    launchctl unload "$plist" >/dev/null 2>&1 || true
    if launchctl load -w "$plist" 2>/dev/null; then
      log_ok "Scheduled ($interval) via launchd: $plist"
    else
      log_warn "wrote plist but 'launchctl load' failed; load it manually: launchctl load -w $plist"
    fi
  else
    log_warn "launchctl not found; plist written to $plist (load it when available)"
  fi
  log_info "  logs: $CCB_SCHED_LOG"
}

ccb_unsched_launchd() {
  local plist; plist="$(ccb_launchd_plist)"
  if [ -f "$plist" ]; then
    command -v launchctl >/dev/null 2>&1 && launchctl unload "$plist" >/dev/null 2>&1 || true
    rm -f "$plist" && log_ok "Removed launchd schedule: $plist"
  else
    log_info "No launchd schedule installed."
  fi
}

# ccb_xml_escape <s> - escape &, <, > for an XML <string> value.
ccb_xml_escape() {
  local s="$1"; s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Linux: systemd user timer
# ---------------------------------------------------------------------------
ccb_systemd_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

ccb_systemd_dir() { printf '%s/systemd/user\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# ccb_sched_systemd <interval> <hh> <mm> <bin> <args...>
ccb_sched_systemd() {
  local interval="$1" hh="$2" mm="$3"; shift 3
  local dir; dir="$(ccb_systemd_dir)"
  mkdir -p "$dir" || die "cannot create systemd user dir: $dir"

  # OnCalendar expression per interval.
  local oncal
  case "$interval" in
    hourly) oncal="*-*-* *:$mm:00" ;;
    daily)  oncal="*-*-* $hh:$mm:00" ;;
    weekly) oncal="Sun *-*-* $hh:$mm:00" ;;
  esac

  # Build a quoted ExecStart line.
  local exec_line="/bin/bash" a
  for a in "$@"; do exec_line="$exec_line $(ccb_sdquote "$a")"; done

  {
    printf '[Unit]\nDescription=claude-code-backup scheduled backup\n\n'
    printf '[Service]\nType=oneshot\nExecStart=%s\n' "$exec_line"
  } >"$dir/$CCB_SCHED_UNIT.service" || die "cannot write service unit"

  {
    printf '[Unit]\nDescription=claude-code-backup timer (%s)\n\n' "$interval"
    printf '[Timer]\nOnCalendar=%s\nPersistent=true\n\n' "$oncal"
    printf '[Install]\nWantedBy=timers.target\n'
  } >"$dir/$CCB_SCHED_UNIT.timer" || die "cannot write timer unit"

  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if systemctl --user enable --now "$CCB_SCHED_UNIT.timer" >/dev/null 2>&1; then
    log_ok "Scheduled ($interval) via systemd user timer: $CCB_SCHED_UNIT.timer"
    log_info "  status: systemctl --user list-timers '$CCB_SCHED_UNIT*'"
  else
    log_warn "wrote units but enabling failed; try: systemctl --user enable --now $CCB_SCHED_UNIT.timer"
  fi
}

ccb_unsched_systemd() {
  local dir; dir="$(ccb_systemd_dir)"
  [ -f "$dir/$CCB_SCHED_UNIT.timer" ] || return 0
  systemctl --user disable --now "$CCB_SCHED_UNIT.timer" >/dev/null 2>&1 || true
  rm -f "$dir/$CCB_SCHED_UNIT.timer" "$dir/$CCB_SCHED_UNIT.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  log_ok "Removed systemd schedule: $CCB_SCHED_UNIT.timer"
}

# ---------------------------------------------------------------------------
# Linux fallback: crontab
# ---------------------------------------------------------------------------
# ccb_sched_cron <interval> <hh> <mm> <bin> <args...>
ccb_sched_cron() {
  local interval="$1" hh="$2" mm="$3"; shift 3
  command -v crontab >/dev/null 2>&1 || die "neither systemd --user nor crontab is available"

  local sched
  case "$interval" in
    hourly) sched="$((10#$mm)) * * * *" ;;
    daily)  sched="$((10#$mm)) $((10#$hh)) * * *" ;;
    weekly) sched="$((10#$mm)) $((10#$hh)) * * 0" ;;
  esac

  local cmd="/bin/bash" a
  for a in "$@"; do cmd="$cmd $(ccb_shquote "$a")"; done
  cmd="$cmd >> $(ccb_shquote "$CCB_SCHED_LOG") 2>&1"

  # Rewrite the crontab, replacing any prior claude-code-backup block.
  local current; current="$(crontab -l 2>/dev/null || true)"
  local filtered; filtered="$(printf '%s\n' "$current" | sed "/$CCB_CRON_BEGIN/,/$CCB_CRON_END/d")"
  {
    printf '%s\n' "$filtered" | sed '/^$/d'
    printf '%s\n' "$CCB_CRON_BEGIN"
    printf '%s %s\n' "$sched" "$cmd"
    printf '%s\n' "$CCB_CRON_END"
  } | crontab - && log_ok "Scheduled ($interval) via crontab" || die "failed to update crontab"
  log_info "  logs: $CCB_SCHED_LOG"
}

ccb_unsched_cron() {
  command -v crontab >/dev/null 2>&1 || return 0
  local current; current="$(crontab -l 2>/dev/null || true)"
  case "$current" in
    *"$CCB_CRON_BEGIN"*)
      printf '%s\n' "$current" | sed "/$CCB_CRON_BEGIN/,/$CCB_CRON_END/d" | sed '/^$/d' | crontab - \
        && log_ok "Removed crontab schedule" ;;
    *) : ;;
  esac
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
ccb_sched_status() {
  log_step "Scheduled backup status"
  local found=0
  case "$CCB_PLATFORM" in
    macos)
      local plist; plist="$(ccb_launchd_plist)"
      if [ -f "$plist" ]; then
        found=1; _chk ok "launchd agent installed: $plist"
        command -v launchctl >/dev/null 2>&1 && launchctl list 2>/dev/null | grep -q "$CCB_SCHED_LABEL" \
          && _chk ok "agent is loaded" || _chk warn "agent not currently loaded"
      fi ;;
    linux)
      local dir; dir="$(ccb_systemd_dir)"
      if [ -f "$dir/$CCB_SCHED_UNIT.timer" ]; then
        found=1; _chk ok "systemd timer installed: $dir/$CCB_SCHED_UNIT.timer"
        ccb_systemd_available && systemctl --user is-enabled "$CCB_SCHED_UNIT.timer" >/dev/null 2>&1 \
          && _chk ok "timer is enabled" || _chk warn "timer not enabled"
      fi
      if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "$CCB_CRON_BEGIN"; then
        found=1; _chk ok "crontab entry installed"
      fi ;;
  esac
  [ "$found" = "1" ] || _chk warn "no recurring backup is scheduled"
  [ -f "$CCB_SCHED_LOG" ] && _chk ok "log: $CCB_SCHED_LOG"
  return 0
}
