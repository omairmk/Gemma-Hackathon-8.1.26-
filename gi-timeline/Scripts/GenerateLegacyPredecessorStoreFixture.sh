#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
fixture_dir="$repository_root/GITimelineTests/Fixtures/LegacyPredecessorStore"
fixture_parent=${fixture_dir:h}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/legacy-predecessor-generator.XXXXXX")
generator="$work_dir/legacy-predecessor-generator"
staging_dir=""
backup_root=""
backup_dir=""
failed_replacement_dir=""
replacement_started=0
replacement_complete=0
had_previous_fixture=0

cleanup() {
  local fixture_exit_code=$?
  local rollback_complete=1
  trap - EXIT

  if (( replacement_started == 1 && replacement_complete == 0 )); then
    rollback_complete=0
    if [[ -n "$backup_root" && -d "$backup_root" ]]; then
      failed_replacement_dir="$backup_root/failed-replacement"
      if [[ -e "$fixture_dir" ]]; then
        if [[ ! -e "$failed_replacement_dir" ]] && /bin/mv "$fixture_dir" "$failed_replacement_dir"; then
          :
        else
          print -u2 "fixture rollback could not move the failed replacement; reviewed backup retained at $backup_dir"
        fi
      fi
      if (( had_previous_fixture == 1 )); then
        if [[ ! -e "$fixture_dir" && -d "$backup_dir" ]] && /bin/mv "$backup_dir" "$fixture_dir"; then
          rollback_complete=1
          print -u2 "fixture regeneration failed; restored the reviewed predecessor fixture"
        else
          print -u2 "fixture rollback requires manual recovery from $backup_dir"
        fi
      elif [[ ! -e "$fixture_dir" ]]; then
        rollback_complete=1
      fi
    fi
  fi

  if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
    /bin/rm -rf "$staging_dir"
  fi
  if [[ -d "$work_dir" ]]; then
    /bin/rm -rf "$work_dir"
  fi
  if [[ -n "$backup_root" && -d "$backup_root" ]]; then
    if (( replacement_complete == 1 || rollback_complete == 1 )); then
      /bin/rm -rf "$backup_root"
    else
      print -u2 "preserved fixture rollback material at $backup_root"
    fi
  fi
  exit $fixture_exit_code
}
trap cleanup EXIT

# Compile and validate the immutable commit/source contract before creating a
# staging directory or moving the reviewed fixture.
xcrun --sdk macosx swiftc -module-name GITimeline -framework SwiftData -framework CryptoKit \
  "$script_dir/GenerateLegacyPredecessorStoreFixture.swift" \
  -o "$generator"
"$generator" validate "$fixture_dir" "$repository_root"

# Build and validate a complete sibling fixture. SwiftData/SQLite binary
# bookkeeping is not byte-reproducible, so replacement requires explicit review
# of the new pinned manifest identity.
staging_dir=$(mktemp -d "$fixture_parent/.LegacyPredecessorStore.staging.XXXXXX")
chmod 755 "$staging_dir"
"$generator" create "$staging_dir" "$repository_root"
"$generator" manifest "$staging_dir" "$repository_root"
"$generator" verify "$staging_dir" "$repository_root"

# Preserve the prior directory until the staged fixture has replaced it and a
# final verification passes. The EXIT trap restores it after any failed move or
# verification and retains backup material if automatic rollback cannot finish.
if [[ -e "$fixture_dir" && ! -d "$fixture_dir" ]]; then
  print -u2 "refusing to replace non-directory fixture path: $fixture_dir"
  exit 1
fi
backup_root=$(mktemp -d "$fixture_parent/.LegacyPredecessorStore.backup.XXXXXX")
backup_dir="$backup_root/reviewed-fixture"
replacement_started=1
if [[ -d "$fixture_dir" ]]; then
  had_previous_fixture=1
  /bin/mv "$fixture_dir" "$backup_dir"
fi
/bin/mv "$staging_dir" "$fixture_dir"
staging_dir=""
"$generator" verify "$fixture_dir" "$repository_root"
replacement_complete=1

shasum -a 256 "$fixture_dir/legacy-predecessor-store-manifest.json" \
  "$fixture_dir/legacy-predecessor.store" \
  "$fixture_dir/legacy-predecessor.store-shm" \
  "$fixture_dir/legacy-predecessor.store-wal"
