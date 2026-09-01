#!/bin/zsh

# One canonical fixed-string set for public encrypted-recovery surfaces that
# must not appear in shipping source or executable payloads. Historical and
# explicitly deferred Release documents are intentionally outside these gates.
typeset -ga RETIRED_RECOVERY_SURFACE_MARKERS=(
  "JournalArchive"
  "ArchiveStaging"
  "RecoveryArchive"
  "GIJournalRecovery"
  "giJournalBackup"
  "privateBackupRecoveryKey"
  "GIJOURNAL-PRIVATE-BACKUP"
  "GI_JOURNAL_PRIVATE_BACKUP"
  "com.omairmkhan.gijournal.backup"
  "encrypted recovery"
  "recovery archive"
  "recovery key"
  "recovery file"
  "separate key"
  "private backup"
  "Create private backup"
  "Export recovery"
  "Import recovery"
  "Restore journal"
  "Copy recovery key"
  "UIDocumentPickerViewController"
)
readonly RETIRED_RECOVERY_SURFACE_MARKERS

retired_recovery_surface_marker_in_file() {
  local inspected_file="${1:?a file to inspect is required}"
  local prohibited_marker
  for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
    if /usr/bin/grep -Fqi -- "$prohibited_marker" "$inspected_file"; then
      print -r -- "$prohibited_marker"
      return 0
    fi
  done
  return 1
}
