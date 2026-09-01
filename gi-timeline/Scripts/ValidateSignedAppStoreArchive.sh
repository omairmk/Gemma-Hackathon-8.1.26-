#!/bin/zsh

set -euo pipefail

readonly archive_path="${1:?usage: ValidateSignedAppStoreArchive.sh /absolute/path/App.xcarchive EXPECTED_TEAM_ID EXPECTED_MARKETING_VERSION EXPECTED_BUILD_NUMBER EXPECTED_SOURCE_COMMIT EXPECTED_SOURCE_TREE EXPECTED_PRIVACY_URL EXPECTED_SUPPORT_URL}"
readonly expected_team_id="${2:?expected Apple Developer Team ID is required}"
readonly expected_marketing_version="${3:?expected marketing version is required}"
readonly expected_build_number="${4:?expected build number is required}"
readonly expected_source_commit="${5:?expected source commit is required}"
readonly expected_source_tree="${6:?expected source tree is required}"
readonly expected_privacy_url="${7:?expected public privacy URL is required}"
readonly expected_support_url="${8:?expected public support URL is required}"
readonly script_directory="${0:A:h}"

fail() {
  print -u2 -- "error: signed App Store archive validation failed: $1"
  exit 1
}

[[ "$expected_marketing_version" == "1.0" ]] \
  || fail "Build 8 marketing version is frozen at 1.0"
[[ "$expected_build_number" == "8" ]] \
  || fail "Build 8 bundle version is frozen at 8"

print -u2 -- "note: ValidateSignedAppStoreArchive.sh is a compatibility wrapper; the release runbook uses the explicit pre-export and exported-IPA gates."
"$script_directory/ValidateDevelopmentSignedAppStoreArchive.sh" \
  "$archive_path" \
  "$expected_team_id" \
  "$expected_source_commit" \
  "$expected_source_tree" \
  "$expected_privacy_url" \
  "$expected_support_url"

readonly signing_identity="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:SigningIdentity' "$archive_path/Info.plist" 2>/dev/null)"
case "$signing_identity" in
  *"Apple Distribution"*|*"iPhone Distribution"*) ;;
  *) fail "compatibility distribution gate requires an Apple Distribution archive" ;;
esac

print -- "SIGNED_APPSTORE_ARCHIVE_VALIDATION: PASS"
print -- "compatibility_wrapper=true primary_preexport_gate=ValidateDevelopmentSignedAppStoreArchive.sh identity=${signing_identity} team=${expected_team_id} version=${expected_marketing_version} build=${expected_build_number} source_commit=${expected_source_commit} source_tree=${expected_source_tree}"
