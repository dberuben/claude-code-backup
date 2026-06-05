# shellcheck shell=bash
#
# platform.sh - Platform detection and portable wrappers for BSD/GNU differences.
#
# This library MUST NOT use GNU-only flags. macOS ships BSD coreutils, so every
# helper here branches on $CCB_PLATFORM where the tools differ (stat, date, etc).
#
# Sourced by common.sh. Do not run directly.

# Detect the host platform from `uname -s`. Sets the global CCB_PLATFORM to one
# of: macos, linux, unknown.
detect_platform() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) CCB_PLATFORM="macos" ;;
    Linux)  CCB_PLATFORM="linux" ;;
    *)      CCB_PLATFORM="unknown" ;;
  esac
  export CCB_PLATFORM
}

# Return 0 if the current platform is supported (macOS or Linux).
platform_supported() {
  [ "${CCB_PLATFORM:-}" = "macos" ] || [ "${CCB_PLATFORM:-}" = "linux" ]
}

# Print a human-readable OS version string.
os_version() {
  case "${CCB_PLATFORM:-}" in
    macos)
      if command -v sw_vers >/dev/null 2>&1; then
        printf 'macOS %s (%s)\n' "$(sw_vers -productVersion 2>/dev/null)" "$(uname -m)"
      else
        printf 'macOS %s\n' "$(uname -r)"
      fi
      ;;
    linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        ( . /etc/os-release; printf '%s (%s)\n' "${PRETTY_NAME:-Linux}" "$(uname -m)" )
      else
        printf 'Linux %s (%s)\n' "$(uname -r)" "$(uname -m)"
      fi
      ;;
    *)
      printf 'Unknown (%s)\n' "$(uname -s 2>/dev/null || echo unknown)"
      ;;
  esac
}

# file_mtime <path> - print the modification time of a file as a Unix epoch.
# BSD stat uses -f %m, GNU stat uses -c %Y.
file_mtime() {
  local path="$1"
  case "${CCB_PLATFORM:-}" in
    macos) stat -f %m "$path" 2>/dev/null ;;
    *)     stat -c %Y "$path" 2>/dev/null ;;
  esac
}

# file_size <path> - print the size of a file in bytes.
# BSD stat uses -f %z, GNU stat uses -c %s.
file_size() {
  local path="$1"
  case "${CCB_PLATFORM:-}" in
    macos) stat -f %z "$path" 2>/dev/null ;;
    *)     stat -c %s "$path" 2>/dev/null ;;
  esac
}
