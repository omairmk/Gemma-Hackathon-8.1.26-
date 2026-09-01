#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
source "${script_directory}/RetiredRecoverySurfaceMarkers.zsh"

fail() {
  print -u2 -- "RETIRED_RECOVERY_SURFACE_NEGATIVE_TEST: FAIL: $1"
  exit 1
}

readonly temporary_directory="$(/usr/bin/mktemp -d /tmp/GIRetiredRecoverySurface.XXXXXX)"
trap '/bin/rm -rf -- "$temporary_directory"' EXIT

readonly required_markers=("recovery file" "separate key" "UIDocumentPickerViewController")
for required_marker in "${required_markers[@]}"; do
  (( ${RETIRED_RECOVERY_SURFACE_MARKERS[(Ie)$required_marker]} > 0 )) \
    || fail "canonical marker set omits ${required_marker}"
done

for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
  fixture_path="${temporary_directory}/fixture-${RETIRED_RECOVERY_SURFACE_MARKERS[(Ie)$prohibited_marker]}.txt"
  print -r -- "prefix ${prohibited_marker} suffix" > "$fixture_path"
  detected_marker="$(retired_recovery_surface_marker_in_file "$fixture_path")" \
    || fail "canonical predicate accepted ${prohibited_marker}"
  [[ -n "$detected_marker" ]] \
    || fail "canonical predicate returned no marker for ${prohibited_marker}"
done

for validator in \
  ValidateLocalOnlySource.sh \
  ValidateAppStoreBuild.sh \
  ValidateDevelopmentSignedAppStoreArchive.sh \
  ValidateExportedAppStoreIPA.sh; do
  validator_path="${script_directory}/${validator}"
  /usr/bin/grep -Fq 'RetiredRecoverySurfaceMarkers.zsh' "$validator_path" \
    || fail "${validator} does not source the canonical marker set"
  /usr/bin/grep -Fq 'RETIRED_RECOVERY_SURFACE_MARKERS' "$validator_path" \
    || fail "${validator} does not enforce the canonical marker set"
done

print -- "RETIRED_RECOVERY_SURFACE_NEGATIVE_TEST: PASS markers=${#RETIRED_RECOVERY_SURFACE_MARKERS} validators=4"
