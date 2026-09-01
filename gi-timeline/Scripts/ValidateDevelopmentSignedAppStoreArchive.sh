#!/bin/zsh

set -euo pipefail

readonly archive_path="${1:?usage: ValidateDevelopmentSignedAppStoreArchive.sh /absolute/path/App.xcarchive EXPECTED_TEAM_ID EXPECTED_SOURCE_COMMIT EXPECTED_SOURCE_TREE EXPECTED_PRIVACY_URL EXPECTED_SUPPORT_URL}"
readonly expected_team_id="${2:?expected Apple Developer Team ID is required}"
readonly expected_source_commit="${3:?expected source commit is required}"
readonly expected_source_tree="${4:?expected source tree is required}"
readonly expected_privacy_url="${5:?expected public privacy URL is required}"
readonly expected_support_url="${6:?expected public support URL is required}"

readonly expected_bundle_id="com.omairmkhan.GITimeline"
readonly expected_display_name="GI Journal"
readonly expected_marketing_version="1.0"
readonly expected_build_number="8"
readonly expected_minimum_os_version="17.0"
readonly expected_camera_usage="GI Journal uses the camera to attach a photo to a manual journal entry."
readonly maximum_uncompressed_bytes=750000000
readonly maximum_text_segment_bytes=250000000
readonly script_directory="${0:A:h}"
source "${script_directory}/RetiredRecoverySurfaceMarkers.zsh"

fail() {
  print -u2 -- "error: development-signed App Store archive validation failed: $1"
  exit 1
}

validate_public_url() {
  local public_url="$1"
  local authority
  [[ "$public_url" == https://* ]] || fail "privacy/support URLs must use HTTPS"
  [[ "$public_url" != *example.invalid* && "$public_url" != *REQUIRED* \
    && "$public_url" != *PLACEHOLDER* && "$public_url" != *" "* && "$public_url" != *@* ]] \
    || fail "privacy/support URL contains a test value, placeholder, whitespace, or user information"
  authority="${public_url#https://}"
  authority="${authority%%/*}"
  [[ -n "$authority" ]] || fail "privacy/support URL has no host"
  print -r -- "$authority" \
    | /usr/bin/grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$' \
    || fail "privacy/support URL must use a public DNS hostname without a port"
  case "${authority:l}" in
    localhost|*.local|*.internal|*.invalid|*.test|*.example) fail "privacy/support URL uses a reserved or non-public hostname" ;;
  esac
}

validated_profile_expiration() {
  local profile_plist="$1"
  /usr/bin/python3 - "$profile_plist" <<'PY'
import datetime
import plistlib
import sys

with open(sys.argv[1], "rb") as profile_file:
    profile = plistlib.load(profile_file)
expiration = profile.get("ExpirationDate")
if not isinstance(expiration, datetime.datetime):
    raise SystemExit("profile has no valid ExpirationDate")
if expiration.tzinfo is None:
    expiration = expiration.replace(tzinfo=datetime.timezone.utc)
if expiration <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit(f"profile expired at {expiration.isoformat()}")
print(expiration.astimezone(datetime.timezone.utc).isoformat())
PY
}

validate_privacy_api_entry() {
  local manifest="$1"
  local index="$2"
  local expected_category="$3"
  local expected_reason="$4"
  local entry_path="NSPrivacyAccessedAPITypes.${index}"
  local category reason_count reason
  category="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPIType" raw "$manifest" 2>/dev/null)" \
    || fail "privacy manifest is missing API entry ${index}"
  [[ "$category" == "$expected_category" ]] \
    || fail "privacy API entry ${index} is ${category}, expected ${expected_category}"
  reason_count="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons" xml1 -o - "$manifest" \
    | /usr/bin/grep -c '<string>')"
  [[ "$reason_count" == "1" ]] \
    || fail "privacy API entry ${expected_category} must contain exactly one reason"
  reason="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons.0" raw "$manifest" 2>/dev/null)" \
    || fail "privacy API entry ${expected_category} has no reason"
  [[ "$reason" == "$expected_reason" ]] \
    || fail "privacy API entry ${expected_category} uses ${reason}, expected ${expected_reason}"
}

validate_privacy_manifest() {
  local manifest="$1"
  [[ -f "$manifest" ]] || fail "privacy manifest is missing"
  /usr/bin/plutil -lint "$manifest" >/dev/null || fail "privacy manifest is invalid"
  [[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw "$manifest" 2>/dev/null)" == "false" ]] \
    || fail "privacy tracking must be false"
  [[ "$(/usr/bin/plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
    || fail "collected data types must be empty"
  [[ "$(/usr/bin/plutil -extract NSPrivacyTrackingDomains xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
    || fail "tracking domains must be empty"
  [[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$manifest" | /usr/bin/grep -c '<dict>')" == "4" ]] \
    || fail "app privacy manifest contains an unreviewed accessed-API declaration"
  validate_privacy_api_entry "$manifest" 0 NSPrivacyAccessedAPICategoryUserDefaults CA92.1
  validate_privacy_api_entry "$manifest" 1 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
  validate_privacy_api_entry "$manifest" 2 NSPrivacyAccessedAPICategoryDiskSpace E174.1
  validate_privacy_api_entry "$manifest" 3 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1
}

validate_runtime_payload_absence() {
  local app_path="$1"
  local unexpected_payload
  unexpected_payload="$(/usr/bin/find "$app_path" \( -type f -o -type l -o -type d \) \( \
    -iname '*litert*' -o -iname '*gemma*' -o -iname '*qwen*' -o -iname '*mlx*' \
    -o -name '*.litertlm' -o -name '*.safetensors' -o -name '*.gguf' \
  \) -print -quit)"
  [[ -z "$unexpected_payload" ]] \
    || fail "manual fallback archive contains a retired AI runtime/model item: ${unexpected_payload#$app_path/}"
  [[ ! -e "${app_path}/EmbeddedModels" && ! -L "${app_path}/EmbeddedModels" ]] \
    || fail "manual fallback archive contains an EmbeddedModels directory"
}

validate_notices() {
  local notices_path="$1"
  [[ -f "$notices_path" ]] || fail "ThirdPartyNotices.txt is missing"
  /usr/bin/grep -Fq "No third-party model or inference runtime is bundled" "$notices_path" \
    || fail "ThirdPartyNotices.txt does not describe the reviewed dependency-free runtime"
  local prohibited_notice
  for prohibited_notice in LiteRT Gemma Qwen MLX; do
    ! /usr/bin/grep -Fq "$prohibited_notice" "$notices_path" \
      || fail "ThirdPartyNotices.txt contains retired runtime notice ${prohibited_notice}"
  done
}

validate_closed_payload() {
  local app_path="$1"
  local bundled_item relative_path
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    fail "bundle contains a symlink: ${relative_path}"
  done < <(/usr/bin/find "$app_path" -type l -print0)
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    case "$relative_path" in
      AppIcon60x60@2x.png|AppIcon76x76@2x~ipad.png|Assets.car|GITimeline|Info.plist|PkgInfo|PrivacyInfo.xcprivacy|ThirdPartyNotices.txt|embedded.mobileprovision|_CodeSignature/CodeResources) ;;
      *) fail "bundle contains an unreviewed file: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" -type f -print0)
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    [[ "$bundled_item" == "$app_path" ]] && relative_path="."
    case "$relative_path" in
      .|_CodeSignature|Frameworks) ;;
      *) fail "bundle contains an unreviewed directory: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" -type d -print0)
}

single_arm64_uuid() {
  local binary_path="$1"
  local artifact_label="$2"
  local uuid_output uuid_count binary_uuid binary_arch
  uuid_output="$(/usr/bin/dwarfdump --uuid "$binary_path")" \
    || fail "could not read ${artifact_label} executable UUID"
  uuid_count="$(print -r -- "$uuid_output" | /usr/bin/grep -c '^UUID:')"
  [[ "$uuid_count" == "1" ]] || fail "${artifact_label} executable must contain one architecture"
  binary_uuid="$(print -r -- "$uuid_output" | /usr/bin/awk '$1 == "UUID:" && !printed { print $2; printed=1 }')"
  binary_arch="$(print -r -- "$uuid_output" | /usr/bin/awk '$1 == "UUID:" && !printed { gsub(/[()]/, "", $3); print $3; printed=1 }')"
  [[ "$binary_arch" == "arm64" && -n "$binary_uuid" ]] \
    || fail "${artifact_label} executable is not a single arm64 binary"
  print -r -- "$binary_uuid"
}

linkedit_fileoff() {
  local binary_path="$1"
  local artifact_label="$2"
  local fileoff
  fileoff="$(/usr/bin/otool -l "$binary_path" \
    | /usr/bin/awk '$1 == "segname" && $2 == "__LINKEDIT" { found=1; next } found && !printed && $1 == "fileoff" { print $2; printed=1 }')"
  [[ "$fileoff" == <-> ]] || fail "could not measure ${artifact_label} __LINKEDIT offset"
  (( fileoff > 16384 && (fileoff - 16384) % 16384 == 0 )) \
    || fail "${artifact_label} __LINKEDIT offset is incompatible with invariant hashing"
  (( $(/usr/bin/stat -f '%z' "$binary_path") > fileoff )) \
    || fail "${artifact_label} executable is truncated before __LINKEDIT"
  print -r -- "$fileoff"
}

normalized_macho_sha256() {
  local binary_path="$1"
  local fileoff="$2"
  local artifact_label="$3"
  local invariant_sha256
  invariant_sha256="$(/usr/bin/python3 "$script_directory/NormalizedMachOExecutableHash.py" "$binary_path" "$fileoff")" \
    || fail "could not normalize/hash ${artifact_label} executable"
  [[ ${#invariant_sha256} == 64 && "$invariant_sha256" != *[^0-9a-f]* ]] \
    || fail "could not hash ${artifact_label} signing-invariant executable payload"
  print -r -- "$invariant_sha256"
}

[[ "$archive_path" == /* ]] || fail "archive path must be absolute"
[[ -d "$archive_path" && -f "$archive_path/Info.plist" ]] || fail "archive or Info.plist is missing"
[[ ${#expected_team_id} == 10 && "$expected_team_id" != *[^A-Z0-9]* ]] || fail "expected team ID must be ten uppercase letters/digits"
[[ ${#expected_source_commit} == 40 && "$expected_source_commit" != *[^0-9a-f]* ]] \
  || fail "expected source commit must be a 40-character lowercase Git commit"
[[ ${#expected_source_tree} == 40 && "$expected_source_tree" != *[^0-9a-f]* ]] \
  || fail "expected source tree must be a 40-character lowercase Git tree"
validate_public_url "$expected_privacy_url"
validate_public_url "$expected_support_url"

readonly archive_application_path="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$archive_path/Info.plist" 2>/dev/null)"
[[ "$archive_application_path" == "Applications/GITimeline.app" ]] \
  || fail "archive application path is not exactly Applications/GITimeline.app"
readonly app_path="$archive_path/Products/$archive_application_path"
readonly info_path="$app_path/Info.plist"
readonly executable_path="$app_path/GITimeline"
[[ -d "$app_path" && -f "$info_path" && -f "$executable_path" ]] || fail "archived application is incomplete"

/usr/bin/plutil -lint "$info_path" >/dev/null || fail "processed app Info.plist is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_path")" == "$expected_bundle_id" ]] || fail "bundle identifier is not production"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_path")" == "$expected_display_name" ]] || fail "display name drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_path")" == "$expected_marketing_version" ]] || fail "marketing version is not frozen at 1.0"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_path")" == "$expected_build_number" ]] || fail "build number is not frozen at 8"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_path")" == "GITimeline" ]] || fail "app executable name drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$info_path")" == "APPL" ]] || fail "app package type drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$info_path" 2>/dev/null)" == "iPhoneOS" ]] || fail "app does not declare iPhoneOS"
! /usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:1' "$info_path" >/dev/null 2>&1 || fail "app declares an unreviewed second platform"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$info_path")" == "$expected_minimum_os_version" ]] || fail "minimum iOS version drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:0' "$info_path" 2>/dev/null)" == "1" ]] || fail "app is not configured for iPhone"
! /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:1' "$info_path" >/dev/null 2>&1 || fail "app declares an unreviewed second device family"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_path")" == "false" ]] || fail "non-exempt encryption declaration is not false"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GIPrivacyPolicyURL' "$info_path" 2>/dev/null)" == "$expected_privacy_url" ]] || fail "privacy-policy URL does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISupportURL' "$info_path" 2>/dev/null)" == "$expected_support_url" ]] || fail "support URL does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$expected_source_commit" ]] || fail "source commit does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$expected_source_tree" ]] || fail "source tree does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$info_path" 2>/dev/null)" == "$expected_camera_usage" ]] || fail "camera usage description drifted"
for prohibited_key in CFBundleDocumentTypes CFBundleURLTypes UTExportedTypeDeclarations UTImportedTypeDeclarations UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
  ! /usr/libexec/PlistBuddy -c "Print :${prohibited_key}" "$info_path" >/dev/null 2>&1 || fail "public app exposes a document, URL, or file-type surface through ${prohibited_key}"
done

validate_runtime_payload_absence "$app_path"
validate_privacy_manifest "$app_path/PrivacyInfo.xcprivacy"
validate_notices "$app_path/ThirdPartyNotices.txt"
[[ -f "$app_path/Assets.car" ]] || fail "compiled assets are missing"
validate_closed_payload "$app_path"

[[ "$(/usr/bin/stat -f '%Lp' "$executable_path")" == "755" ]] \
  || fail "main executable is not mode 0755"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$executable_path" 2 17.0 \
  || fail "main executable platform/minimum OS drifted"
readonly app_uuid="$(single_arm64_uuid "$executable_path" "archive")"
readonly app_linkedit_fileoff="$(linkedit_fileoff "$executable_path" "archive")"
readonly app_normalized_sha256="$(normalized_macho_sha256 "$executable_path" "$app_linkedit_fileoff" "archive")"

readonly entitlements_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-archive-entitlements.XXXXXX")"
readonly profile_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-archive-profile.XXXXXX")"
readonly strings_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-archive-strings.XXXXXX")"
cleanup() {
  /bin/rm -f "$entitlements_dump" "$profile_dump" "$strings_dump"
}
trap cleanup EXIT

/usr/bin/codesign --verify --strict "$app_path" || fail "app signature is invalid"
readonly codesign_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"
[[ "$codesign_details" == *$'\nIdentifier='"$expected_bundle_id"$'\n'* || "$codesign_details" == Identifier="$expected_bundle_id"$'\n'* ]] \
  || fail "signed code identifier does not match the production bundle ID"
[[ "$codesign_details" == *$'\nTeamIdentifier='"$expected_team_id"$'\n'* ]] || fail "signed code team identifier does not match"
case "$codesign_details" in
  *"Authority=Apple Distribution:"*|*"Authority=iPhone Distribution:"*) readonly signing_class="distribution" ;;
  *"Authority=Apple Development:"*|*"Authority=iPhone Developer:"*) readonly signing_class="development" ;;
  *) fail "archive is not signed by an Apple development or distribution identity" ;;
esac

/usr/bin/codesign -d --entitlements :- "$app_path" > "$entitlements_dump" 2>/dev/null || fail "signed entitlements could not be read"
/usr/bin/plutil -lint "$entitlements_dump" >/dev/null || fail "signed entitlements are not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$entitlements_dump" 2>/dev/null)" == "${expected_team_id}.${expected_bundle_id}" ]] \
  || fail "application-identifier entitlement does not match the production App ID"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements_dump" 2>/dev/null)" == "$expected_team_id" ]] \
  || fail "team entitlement does not match"
if [[ "$signing_class" == "distribution" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements_dump" 2>/dev/null || true)" != "true" ]] \
    || fail "distribution archive permits debugging"
else
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements_dump" 2>/dev/null || true)" == "true" ]] \
    || fail "development archive is missing get-task-allow"
fi

readonly embedded_profile="$app_path/embedded.mobileprovision"
[[ -f "$embedded_profile" ]] || fail "embedded provisioning profile is missing"
/usr/bin/security cms -D -i "$embedded_profile" > "$profile_dump" 2>/dev/null || fail "embedded profile could not be decoded"
/usr/bin/plutil -lint "$profile_dump" >/dev/null || fail "embedded provisioning profile is invalid"
typeset profile_expiration
profile_expiration="$(validated_profile_expiration "$profile_dump")" \
  || fail "embedded provisioning profile is expired or has no valid expiration"
readonly profile_expiration
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_dump" 2>/dev/null)" == "$expected_team_id" ]] || fail "profile team does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_dump" 2>/dev/null)" == "${expected_team_id}.${expected_bundle_id}" ]] || fail "profile does not authorize the production App ID"
if [[ "$signing_class" == "distribution" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile_dump" 2>/dev/null || true)" != "true" ]] || fail "distribution profile permits debugging"
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile_dump" >/dev/null 2>&1 || fail "distribution profile contains provisioned devices"
fi

/usr/bin/strings -a "$executable_path" > "$strings_dump" || fail "could not inspect production executable strings"
for prohibited_marker in \
  "--show-developer-tools" \
  "--ui-test-ephemeral-store" \
  "--run-overnight-gemma-smoke" \
  "--run-embedded-gemma-smoke" \
  "--internal-app-store-raw-image-v1" \
  "--run-physical-raw-image" \
  "--run-photo-evaluation-derived-map-iphone" \
  "--run-photo-tuning-derived-map-v3" \
  "--run-photo-blind-validation-v3" \
  "Qwen3HybridPhotoSuggestionEngine"; do
  ! /usr/bin/grep -Fq -- "$prohibited_marker" "$strings_dump" || fail "production executable contains prohibited marker ${prohibited_marker}"
done
for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
  ! /usr/bin/grep -Fqi -- "$prohibited_marker" "$strings_dump" || fail "production executable contains retired recovery marker ${prohibited_marker}"
done

typeset -i app_text_bytes app_regular_file_bytes=0 archive_regular_file_bytes=0
app_text_bytes="$(/usr/bin/size -m "$executable_path" | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
(( app_text_bytes > 0 )) || fail "could not measure executable __TEXT segment"
(( app_text_bytes < maximum_text_segment_bytes )) || fail "executable __TEXT bytes reach or exceed the release ceiling"
while IFS= read -r -d $'\0' bundled_file; do (( app_regular_file_bytes += $(/usr/bin/stat -f '%z' "$bundled_file") )); done < <(/usr/bin/find "$app_path" -type f -print0)
(( app_regular_file_bytes < maximum_uncompressed_bytes )) || fail "app regular-file bytes reach or exceed the release ceiling"
while IFS= read -r -d $'\0' archive_file; do (( archive_regular_file_bytes += $(/usr/bin/stat -f '%z' "$archive_file") )); done < <(/usr/bin/find "$archive_path" -type f -print0)
(( archive_regular_file_bytes < maximum_uncompressed_bytes )) || fail "archive regular-file bytes reach or exceed the release ceiling"

print -- "DEVELOPMENT_SIGNED_APPSTORE_ARCHIVE_VALIDATION: PASS"
print -- "preexport_only=true exported_ipa_not_validated=true signing_class=${signing_class} team=${expected_team_id} profile_expiration=${profile_expiration} bundle_id=${expected_bundle_id} version=${expected_marketing_version} build=${expected_build_number} source_commit=${expected_source_commit} source_tree=${expected_source_tree} app_uuid=${app_uuid} app_normalized_sha256=${app_normalized_sha256} app_regular_file_bytes=${app_regular_file_bytes} archive_regular_file_bytes=${archive_regular_file_bytes} model_payload=absent runtime_payload=absent"
