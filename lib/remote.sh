# shellcheck shell=bash
#
# remote.sh - Push a finished backup to an off-machine destination.
#
# Transport is a user-supplied command, so claude-code-backup stays zero-
# dependency and can target anything (rclone, rsync/scp, aws s3, git, …) without
# bundling integrations. The spec format is:
#
#   cmd:<command>      Run <command> via `sh -c`. If it contains the token "{}",
#                      every "{}" is replaced by the archive path; otherwise the
#                      archive path is appended as the final argument.
#
# A bare spec with no "cmd:" prefix is also accepted and treated as "cmd:".
#
# Examples:
#   --remote 'cmd:rclone copy {} mydrive:claude-backups/'
#   --remote 'cmd:rsync -a {} nas:/backups/claude/'
#   --remote 'cmd:aws s3 cp {} s3://my-bucket/claude/'
#   CLAUDE_BACKUP_REMOTE='cmd:scp {} host:/backups/' claude-backup
#
# Sourced by common.sh. Not run directly.

# ccb_remote_run <command-template> <file> - run one transport command for one
# file, substituting "{}" or appending the path. Returns the command's status.
#
# The file path is passed to `sh -c` as a positional argument ($1), never spliced
# into the command string. We only substitute the literal token "$1" for "{}",
# so a path containing $(…), backticks, quotes or spaces stays inert DATA rather
# than becoming shell CODE (the archive name embeds the host's `hostname`, which
# the running user may not fully control). The command template itself is the
# user's own intentional input, so executing it is by design.
ccb_remote_run() {
  local tmpl="$1" file="$2" cmd
  if printf '%s' "$tmpl" | grep -q '{}'; then
    cmd="${tmpl//\{\}/\"\$1\"}"   # {}  ->  "$1"
  else
    cmd="$tmpl \"\$1\""            # append "$1"
  fi
  # $0 is set to "ccb-remote" (cosmetic); $1 carries the path safely.
  sh -c "$cmd" ccb-remote "$file"
}

# ccb_push_remote <archive> <spec> - push the archive (and its .sha256 sidecar,
# if present) using <spec>. Returns non-zero if the archive push fails. A failed
# sidecar push is only a warning. Never deletes or alters the local backup.
ccb_push_remote() {
  local archive="$1" spec="$2" tmpl rc
  case "$spec" in
    cmd:*) tmpl="${spec#cmd:}" ;;
    *)     tmpl="$spec" ;;        # tolerate a bare command with no prefix
  esac
  [ -n "$tmpl" ] || { log_warn "empty --remote spec; nothing to push"; return 1; }

  log_step "Pushing backup to remote…"
  if ccb_remote_run "$tmpl" "$archive"; then
    rc=0
    log_ok "Remote push complete: $(basename "$archive")"
  else
    rc=$?
    log_err "remote push failed (exit $rc): $(basename "$archive")"
  fi

  # Best-effort: also ship the checksum sidecar so the remote copy is verifiable.
  if [ "$rc" = "0" ] && [ -f "$archive.sha256" ]; then
    ccb_remote_run "$tmpl" "$archive.sha256" \
      || log_warn "remote push of checksum sidecar failed (archive itself was pushed)"
  fi
  return "$rc"
}

# do_push - implements `claude-backup push [--from <archive>] --remote <spec>`.
# Pushes an already-created backup; defaults to the latest one. Reads OPT_*.
do_push() {
  local spec="${OPT_REMOTE:-${CLAUDE_BACKUP_REMOTE:-}}"
  [ -n "$spec" ] || die "no remote specified; use --remote <spec> or set CLAUDE_BACKUP_REMOTE"

  local archive="${OPT_FROM:-}"
  if [ -z "$archive" ]; then
    archive="$(latest_backup "$(resolve_backup_dir "${OPT_DEST:-}")")"
    [ -n "$archive" ] || die "no backup found; use --from <archive> or run 'claude-backup' first"
    log_info "Selected latest backup: $archive"
  fi
  [ -f "$archive" ] || die "archive not found: $archive"

  ccb_push_remote "$archive" "$spec"
}
