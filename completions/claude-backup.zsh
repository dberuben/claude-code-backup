#compdef claude-backup claude-restore
# zsh completion for claude-code-backup
# Install: place at <prefix>/share/zsh/site-functions/_claude-backup
# and ensure that directory is on your $fpath.

_claude-backup() {
  local -a subcommands opts
  subcommands=(
    'list:List existing backups'
    'verify:Check an archive (gzip + checksum)'
    'push:Push an existing backup to a remote'
    'schedule:Install a recurring backup'
    'unschedule:Remove the recurring backup'
    'doctor:Diagnose the environment'
    'banner:Print the status banner'
  )
  opts=(
    '--dest[Backup destination directory]:directory:_files -/'
    '--include-project[Include project config]'
    '--no-project[Exclude project config]'
    '--no-history[Exclude projects/ (history)]'
    '--full[Include everything (no pruning)]'
    '--include-env[Include .env.claude/.envrc]'
    '--strict-secrets[Abort if secrets detected]'
    "--remote[Push the archive to a remote]:spec:"
    '--from[Operate on a specific archive]:archive:_files'
    '--daily[Schedule daily]'
    '--weekly[Schedule weekly]'
    '--hourly[Schedule hourly]'
    '--at[Time HH:MM for schedule]:time:'
    '--status[Show schedule status]'
    '--dry-run[Show what would be backed up]'
    '--json[Machine-readable output]'
    '--quiet[Minimal output]'
    '--help[Show help]'
    '--version[Show version]'
  )
  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
  fi
  _arguments $opts
}

_claude-restore() {
  _arguments \
    '--from[Restore from archive]:archive:_files' \
    '--list[List available backups]' \
    '--list-contents[Show categories in an archive]' \
    '--only[Restore only these categories]:categories:(settings agents commands hooks skills mcp claude-md history plugins)' \
    '--dry-run[Show restore plan only]' \
    '--force[Do not ask confirmation]' \
    '--home-only[Restore only global config]' \
    '--project-only[Restore only project config]' \
    '--backup-existing[Pre-restore backup (default)]' \
    '--no-backup-existing[Skip pre-restore backup]' \
    '--dest[Backup directory]:directory:_files -/' \
    '--json[Machine-readable output]' \
    '--help[Show help]' \
    '--version[Show version]'
}

case "$service" in
  claude-backup)  _claude-backup "$@" ;;
  claude-restore) _claude-restore "$@" ;;
esac
