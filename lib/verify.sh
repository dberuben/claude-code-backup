# shellcheck shell=bash
#
# verify.sh - Check the integrity and safety of a backup archive.
#
# Three independent checks, all non-destructive:
#   1. gzip integrity     - `gzip -t` proves the compressed stream is intact.
#   2. checksum           - compare against the `<archive>.sha256` sidecar.
#   3. safe listing       - reuse validate_archive_listing (no absolute / ".." paths).
#
# Sourced by bin/claude-backup (needs validate_archive_listing from restore.sh).
# Not run directly.

# do_verify - implements `claude-backup verify [--from <archive>]`. Reads OPT_*.
# Exit status is 0 only when every applicable check passes.
do_verify() {
  require_cmd tar
  require_cmd gzip

  # --- Select archive -------------------------------------------------------
  local archive="${OPT_FROM:-}"
  if [ -z "$archive" ]; then
    archive="$(latest_backup "$(resolve_backup_dir "${OPT_DEST:-}")")"
    [ -n "$archive" ] || die "no backup found; use --from <archive> or run 'claude-backup' first"
  fi
  [ -f "$archive" ] || die "archive not found: $archive"

  local ok=1
  local gz="fail" sumc="absent" listc="fail"

  # --- 1. gzip integrity ----------------------------------------------------
  if gzip -t "$archive" 2>/dev/null; then gz="ok"; else gz="fail"; ok=0; fi

  # --- 2. checksum ----------------------------------------------------------
  if [ -f "$archive.sha256" ]; then
    if ccb_have_sha256; then
      local want got
      want="$(awk 'NR==1{print $1}' "$archive.sha256" 2>/dev/null)"
      got="$(ccb_sha256 "$archive")"
      if [ -n "$want" ] && [ "$want" = "$got" ]; then sumc="ok"; else sumc="mismatch"; ok=0; fi
    else
      sumc="no-tool"   # sidecar present but we cannot verify it here
    fi
  else
    sumc="absent"      # not an error: older backups have no sidecar
  fi

  # --- 3. safe listing ------------------------------------------------------
  if validate_archive_listing "$archive" >/dev/null 2>&1; then listc="ok"; else listc="fail"; ok=0; fi

  # --- Report ---------------------------------------------------------------
  if [ "$CCB_JSON" = "1" ]; then
    local status="ok"; [ "$ok" = "1" ] || status="fail"
    printf '{"status":"%s","archive":"%s","gzip":"%s","checksum":"%s","listing":"%s","version":"%s"}\n' \
      "$status" "$(json_escape "$archive")" "$gz" "$sumc" "$listc" "$CCB_VERSION"
    [ "$ok" = "1" ]
    return
  fi

  log_step "Verifying $(basename "$archive")"
  case "$gz"   in ok) _chk ok "gzip stream intact" ;; *) _chk fail "gzip integrity check FAILED (archive corrupt)" ;; esac
  case "$sumc" in
    ok)       _chk ok   "checksum matches $archive.sha256" ;;
    mismatch) _chk fail "checksum MISMATCH — archive does not match its .sha256" ;;
    no-tool)  _chk warn "checksum present but no sha256 tool to verify it" ;;
    absent)   _chk warn "no .sha256 sidecar (not checked)" ;;
  esac
  case "$listc" in ok) _chk ok "archive listing is safe (no absolute / parent paths)" ;; *) _chk fail "archive listing contains unsafe paths" ;; esac

  if [ "$ok" = "1" ]; then
    log_ok "Archive verified."
  else
    log_err "Archive verification FAILED."
  fi
  [ "$ok" = "1" ]
}
