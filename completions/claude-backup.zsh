#compdef claude-backup claude-restore
# zsh completion for claude-code-backup
# Install: place at <prefix>/share/zsh/site-functions/_claude-backup
# and ensure that directory is on your $fpath.

_claude-backup() {
  local -a subcommands opts
  subcommands=(
    'list:List existing backups'
    'doctor:Diagnose the environment'
    'banner:Print the status banner'
  )
  opts=(
    '--dest[Backup destination directory]:directory:_files -/'
    '--icloud[Also copy to iCloud Drive (macOS)]'
    '--include-project[Include project config]'
    '--no-project[Exclude project config]'
    '--include-env[Include .env.claude/.envrc]'
    '--strict-secrets[Abort if secrets detected]'
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
