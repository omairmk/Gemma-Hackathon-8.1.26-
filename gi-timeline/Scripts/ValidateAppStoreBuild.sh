#!/bin/zsh

set -euo pipefail

readonly enabled="${APPSTORE_VALIDATION_ENABLED:-NO}"
readonly stamp_path="${APPSTORE_VALIDATION_STAMP:?APPSTORE_VALIDATION_STAMP is required}"
readonly script_directory="${0:A:h}"
readonly physical_team_id="${EXPECTED_PHYSICAL_TEAM_ID:-}"
source "${script_directory}/RetiredRecoverySurfaceMarkers.zsh"

fail() {
  print -u2 -- "error: App Store package validation failed: $1"
  exit 1
}

normalized_condition_set() {
  local conditions="$1"

  if [[ "$conditions" == \"*\" ]]; then
    conditions="${conditions#\"}"
    conditions="${conditions%\"}"
  fi
  print -r -- "$conditions" \
    | /usr/bin/tr -s '[:space:]' '\n' \
    | /usr/bin/sed '/^$/d' \
    | /usr/bin/sort -u \
    | /usr/bin/paste -sd ' ' -
}

validate_app_store_model_gate() {
  local app_root="$1"
  local required_model_size="$2"
  local required_model_sha256="$3"
  local required_model_id="$4"
  local required_model_revision="$5"
  local required_package_resolved_sha256="$6"
  local required_source_commit="$7"
  local required_source_tree="$8"
  local required_model_mtime_epoch="$9"
  local reviewed_model_path="${app_root}/EmbeddedModels/gemma-4-E4B-it.litertlm"
  local reviewed_receipt_path="${app_root}/EmbeddedModels/gemma-4-E4B-it.receipt"
  local model_candidate receipt_key receipt_line
  typeset -a model_paths=()

  [[ "$required_model_size" == <-> ]] || fail "expected model size is not numeric"
  [[ ${#required_model_sha256} == 64 && "$required_model_sha256" != *[^0-9a-f]* ]] \
    || fail "expected model SHA-256 is malformed"
  [[ "$required_model_mtime_epoch" == <-> ]] || fail "expected model modification time is not numeric"

  while IFS= read -r -d $'\0' model_candidate; do
    model_paths+=("$model_candidate")
  done < <(/usr/bin/find "$app_root" \( -type f -o -type l \) -name '*.litertlm' -print0)
  (( ${#model_paths[@]} == 1 )) || fail "bundle must contain exactly one .litertlm model"
  [[ "${model_paths[1]}" == "$reviewed_model_path" ]] || fail "model is not at the reviewed bundle path"
  [[ ! -L "$reviewed_model_path" && -f "$reviewed_model_path" ]] \
    || fail "embedded model must be a regular non-symlink file"
  [[ "$(/usr/bin/stat -f '%z' "$reviewed_model_path")" == "$required_model_size" ]] \
    || fail "embedded model size is wrong"
  [[ "$(/usr/bin/shasum -a 256 "$reviewed_model_path" | /usr/bin/awk '{print $1}')" == "$required_model_sha256" ]] \
    || fail "embedded model SHA-256 is wrong"
  [[ "$(/usr/bin/stat -f '%m' "$reviewed_model_path")" == "$required_model_mtime_epoch" ]] \
    || fail "embedded model modification time is wrong"

  [[ ! -L "$reviewed_receipt_path" && -f "$reviewed_receipt_path" ]] \
    || fail "model/source receipt is missing or is a symlink"
  [[ "$(/usr/bin/tail -c 1 "$reviewed_receipt_path" | /usr/bin/od -An -tuC | /usr/bin/tr -d ' ')" == "10" ]] \
    || fail "model/source receipt must end with exactly one complete newline-terminated field"
  [[ "$(/usr/bin/wc -l < "$reviewed_receipt_path" | /usr/bin/tr -d ' ')" == "10" ]] \
    || fail "model/source receipt does not contain the frozen ten-field record"

  for receipt_key in \
    status \
    model_id \
    source_revision \
    bytes \
    sha256 \
    source_commit \
    source_tree \
    package_resolved_sha256 \
    source_fingerprint \
    destination_fingerprint; do
    [[ "$(/usr/bin/grep -Ec "^${receipt_key}=" "$reviewed_receipt_path")" == "1" ]] \
      || fail "model/source receipt must contain exactly one ${receipt_key} field"
  done

  for receipt_line in \
    "status=verified" \
    "model_id=${required_model_id}" \
    "source_revision=${required_model_revision}" \
    "bytes=${required_model_size}" \
    "sha256=${required_model_sha256}" \
    "source_commit=${required_source_commit}" \
    "source_tree=${required_source_tree}" \
    "package_resolved_sha256=${required_package_resolved_sha256}"; do
    /usr/bin/grep -Fqx "$receipt_line" "$reviewed_receipt_path" \
      || fail "model/source receipt is missing ${receipt_line}"
  done

  [[ "$(/usr/bin/grep -Ec "^source_fingerprint=[0-9]+:[0-9]+:${required_model_size}:[0-9]+$" "$reviewed_receipt_path")" == "1" ]] \
    || fail "source fingerprint receipt is missing or malformed"
  [[ "$(/usr/bin/grep -Ec "^destination_fingerprint=[0-9]+:[0-9]+:${required_model_size}:${required_model_mtime_epoch}$" "$reviewed_receipt_path")" == "1" ]] \
    || fail "destination fingerprint receipt is missing or malformed"
}

validate_manual_fallback_payload_absence() {
  local app_root="$1"
  local unexpected_payload

  unexpected_payload="$(/usr/bin/find "$app_root" \( -type f -o -type l \) -name '*.litertlm' -print -quit)"
  [[ -z "$unexpected_payload" ]] \
    || fail "manual fallback bundle contains a .litertlm model"
  unexpected_payload="$(/usr/bin/find "$app_root" \( -type f -o -type l \) -path '*/EmbeddedModels/*' -print -quit)"
  [[ -z "$unexpected_payload" ]] \
    || fail "manual fallback bundle contains an EmbeddedModels payload"
  [[ ! -e "${app_root}/EmbeddedModels" && ! -L "${app_root}/EmbeddedModels" ]] \
    || fail "manual fallback bundle contains an EmbeddedModels directory"
}

validate_public_url() {
  local public_url="$1"
  local authority
  [[ "$public_url" == https://* ]] || fail "public privacy/support URL must use HTTPS"
  [[ "$public_url" != *example.invalid* && "$public_url" != *REQUIRED* \
    && "$public_url" != *PLACEHOLDER* && "$public_url" != *" "* && "$public_url" != *@* ]] \
    || fail "public privacy/support URL contains a test value, placeholder, whitespace, or user information"
  authority="${public_url#https://}"
  authority="${authority%%/*}"
  [[ -n "$authority" ]] || fail "public privacy/support URL has no host"
  print -r -- "$authority" \
    | /usr/bin/grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$' \
    || fail "public privacy/support URL must use a public DNS hostname without a port"
  case "${authority:l}" in
    localhost|*.local|*.internal|*.invalid|*.test|*.example) fail "public privacy/support URL uses a reserved or non-public hostname" ;;
  esac
}

case "${CONFIGURATION:-}" in
  AppStore)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE MANUAL_FALLBACK_RELEASE" ]] \
      || fail "AppStore must compile with exactly APPSTORE_RELEASE and MANUAL_FALLBACK_RELEASE"
    [[ "$enabled" == "YES" ]] \
      || fail "AppStore package validation cannot be disabled"
    ;;
  AppStoreTesting)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE APPSTORE_RELEASE_TESTING MANUAL_FALLBACK_RELEASE" ]] \
      || fail "AppStoreTesting must compile with exactly APPSTORE_RELEASE, APPSTORE_RELEASE_TESTING, and MANUAL_FALLBACK_RELEASE"
    [[ "$enabled" == "YES" ]] \
      || fail "AppStoreTesting package validation cannot be disabled"
    ;;
  PhysicalQualification)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE" ]] \
      || fail "PhysicalQualification must compile the app with exactly APPSTORE_RELEASE"
    [[ "$enabled" == "YES" ]] \
      || fail "PhysicalQualification package validation cannot be disabled"
    ;;
  *)
    [[ "$enabled" != "YES" ]] \
      || fail "package validation may be enabled only for AppStore, AppStoreTesting, or PhysicalQualification"
    ;;
esac

/bin/mkdir -p "${stamp_path:h}"

if [[ "$enabled" != "YES" ]]; then
  print -r -- "status=disabled" > "$stamp_path"
  exit 0
fi

readonly expected_marketing_version="1.0"
readonly expected_build_number="8"
readonly expected_camera_usage="GI Journal uses the camera to attach a photo to a manual journal entry."
case "${CONFIGURATION:-}" in
  AppStoreTesting)
    readonly expected_bundle_id="com.omairmkhan.GITimeline.appstoretesting"
    readonly expected_supported_platform="iPhoneSimulator"
    readonly expected_macho_platform="7"
    ;;
  PhysicalQualification)
    readonly expected_bundle_id="com.omairmkhan.GITimeline.qualification"
    readonly expected_supported_platform="iPhoneOS"
    readonly expected_macho_platform="2"
    ;;
  *)
    readonly expected_bundle_id="com.omairmkhan.GITimeline"
    readonly expected_supported_platform="iPhoneOS"
    readonly expected_macho_platform="2"
    ;;
esac
readonly expected_model_size="3659530240"
readonly expected_model_sha256="0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
readonly expected_model_mtime_epoch="1704067200"
readonly expected_model_id="litert-community/gemma-4-E4B-it-litert-lm"
readonly expected_revision="28299f30ee4d43294517a4ac93abd6163412f07f"
readonly expected_package_resolved_sha256="90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f"
readonly expected_device_framework_uuid="BD35C88F-B768-3842-B525-B3F54B900F01"
readonly expected_simulator_framework_uuid="4C4C4454-5555-3144-A103-259ECF8844DE"
if [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]]; then
  readonly expected_framework_uuid="$expected_simulator_framework_uuid"
  readonly expected_framework_linkedit_fileoff="26918912"
  readonly expected_framework_normalized_sha256="c22005dbe0406b1700df3e91316f82916039417958abf7c2faef416e83181058"
else
  readonly expected_framework_uuid="$expected_device_framework_uuid"
  readonly expected_framework_linkedit_fileoff="27344896"
  readonly expected_framework_normalized_sha256="cda529609840b50a6d9f638b922a57809bc45f7dc57fd79b111505e6cbe6a183"
fi
readonly build_source_commit="${GI_SOURCE_COMMIT:-}"
readonly build_source_tree="${GI_SOURCE_TREE:-}"
readonly app_path="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${WRAPPER_NAME:?WRAPPER_NAME is required}"
readonly info_path="${app_path}/Info.plist"
readonly model_path="${GEMMA_EMBED_OUTPUT_PATH:?GEMMA_EMBED_OUTPUT_PATH is required}"
readonly model_receipt_path="${GEMMA_EMBED_RECEIPT_OUTPUT_PATH:?GEMMA_EMBED_RECEIPT_OUTPUT_PATH is required}"
readonly app_privacy_path="${app_path}/PrivacyInfo.xcprivacy"
readonly framework_privacy_path="${LITERT_PRIVACY_OUTPUT_PATH:?LITERT_PRIVACY_OUTPUT_PATH is required}"
readonly assets_path="${app_path}/Assets.car"
readonly notices_path="${app_path}/ThirdPartyNotices.txt"
readonly icon_source="${SRCROOT:?SRCROOT is required}/GITimeline/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
readonly executable_path="${app_path}/${EXECUTABLE_NAME:?EXECUTABLE_NAME is required}"
readonly framework_executable_path="${app_path}/Frameworks/CLiteRTLM.framework/CLiteRTLM"
readonly framework_info_path="${app_path}/Frameworks/CLiteRTLM.framework/Info.plist"
readonly maximum_uncompressed_bytes=4000000000
readonly maximum_text_segment_bytes=500000000

[[ "${CONFIGURATION:-}" == "AppStore" || "${CONFIGURATION:-}" == "AppStoreTesting" \
  || "${CONFIGURATION:-}" == "PhysicalQualification" ]] \
  || fail "configuration is ${CONFIGURATION:-unset}, expected AppStore, AppStoreTesting, or PhysicalQualification"
case "${CONFIGURATION:-}" in
  AppStore)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE MANUAL_FALLBACK_RELEASE" ]] \
      || fail "AppStore must compile with exactly APPSTORE_RELEASE and MANUAL_FALLBACK_RELEASE"
    ;;
  AppStoreTesting)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE APPSTORE_RELEASE_TESTING MANUAL_FALLBACK_RELEASE" ]] \
      || fail "AppStoreTesting must compile with exactly APPSTORE_RELEASE, APPSTORE_RELEASE_TESTING, and MANUAL_FALLBACK_RELEASE"
    ;;
  PhysicalQualification)
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE" ]] \
      || fail "PhysicalQualification must compile the app with exactly APPSTORE_RELEASE"
    ;;
esac
[[ "${LITERT_PRIVACY_INJECTION_ENABLED:-NO}" == "YES" ]] || fail "framework privacy injection is disabled"
[[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" == "$expected_bundle_id" ]] || fail "bundle identifier is not production"
[[ "${MARKETING_VERSION:-}" == "$expected_marketing_version" ]] \
  || fail "marketing version must be the frozen candidate ${expected_marketing_version}"
[[ "${CURRENT_PROJECT_VERSION:-}" == "$expected_build_number" ]] \
  || fail "build number must be the frozen candidate ${expected_build_number}"

if [[ "${CONFIGURATION:-}" == "AppStore" || "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
  [[ ${#build_source_commit} == 40 && "$build_source_commit" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} requires a recorded GI_SOURCE_COMMIT"
  [[ ${#build_source_tree} == 40 && "$build_source_tree" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} requires a recorded GI_SOURCE_TREE"
fi
readonly reviewed_model_path="${app_path}/EmbeddedModels/gemma-4-E4B-it.litertlm"
readonly reviewed_receipt_path="${app_path}/EmbeddedModels/gemma-4-E4B-it.receipt"
case "${CONFIGURATION:-}" in
  AppStore|AppStoreTesting)
    [[ "${GEMMA_EMBED_ENABLED:-NO}" == "NO" ]] \
      || fail "manual fallback must disable Gemma embedding"
    [[ "$model_path" == "${DERIVED_FILE_DIR:?DERIVED_FILE_DIR is required}/GemmaEmbedding.model.stamp" ]] \
      || fail "manual fallback model stamp must stay outside the app bundle"
    [[ "$model_receipt_path" == "${DERIVED_FILE_DIR}/GemmaEmbedding.receipt.stamp" ]] \
      || fail "manual fallback receipt stamp must stay outside the app bundle"
    validate_manual_fallback_payload_absence "$app_path"
    ;;
  PhysicalQualification)
    [[ "${GEMMA_EMBED_ENABLED:-NO}" == "YES" ]] || fail "Gemma embedding is disabled"
    [[ "$model_path" == "$reviewed_model_path" ]] \
      || fail "GEMMA_EMBED_OUTPUT_PATH is not the reviewed bundle path"
    [[ "$model_receipt_path" == "$reviewed_receipt_path" ]] \
      || fail "GEMMA_EMBED_RECEIPT_OUTPUT_PATH is not the reviewed bundle path"
    validate_app_store_model_gate \
      "$app_path" \
      "$expected_model_size" \
      "$expected_model_sha256" \
      "$expected_model_id" \
      "$expected_revision" \
      "$expected_package_resolved_sha256" \
      "$build_source_commit" \
      "$build_source_tree" \
      "$expected_model_mtime_epoch"
    ;;
esac
if [[ "${CONFIGURATION:-}" == "AppStore" || "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
  "${SRCROOT}/Scripts/ValidateAppSourceCheckout.sh" "${SRCROOT}" "$build_source_commit" "$build_source_tree" \
    || fail "${CONFIGURATION} source checkout failed byte-for-HEAD validation after compilation"
fi

[[ -f "$info_path" ]] || fail "processed Info.plist is missing"
/usr/bin/plutil -lint "$info_path" >/dev/null || fail "processed Info.plist is invalid"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_path")" == "$expected_bundle_id" ]] \
  || fail "processed bundle identifier drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_path")" == "$MARKETING_VERSION" ]] \
  || fail "processed short version drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_path")" == "$CURRENT_PROJECT_VERSION" ]] \
  || fail "processed build number drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_path")" == "GITimeline" ]] \
  || fail "processed app executable name drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$info_path")" == "APPL" ]] \
  || fail "processed app package type drifted"
[[ "$(/usr/bin/plutil -extract UIDeviceFamily raw -expect array "$info_path" 2>/dev/null)" == "1" ]] \
  || fail "processed app must declare exactly one device family"
[[ "$(/usr/bin/plutil -extract UIDeviceFamily.0 raw -expect integer "$info_path" 2>/dev/null)" == "1" ]] \
  || fail "processed app is not declared for iPhone"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UISupportedInterfaceOrientations:0' "$info_path" 2>/dev/null)" == "UIInterfaceOrientationPortrait" ]] \
  || fail "processed app must declare portrait as its reviewed iPhone orientation"
! /usr/libexec/PlistBuddy -c 'Print :UISupportedInterfaceOrientations:1' "$info_path" >/dev/null 2>&1 \
  || fail "processed app declares an unreviewed second iPhone orientation"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$info_path" 2>/dev/null)" == "$expected_supported_platform" ]] \
  || fail "processed app platform is not ${expected_supported_platform}"
! /usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:1' "$info_path" >/dev/null 2>&1 \
  || fail "processed app declares an unreviewed second platform"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_path")" == "false" ]] \
  || fail "non-exempt encryption declaration is not false"
readonly camera_usage="$(/usr/bin/plutil -extract NSCameraUsageDescription raw -expect string "$info_path" 2>/dev/null)"
[[ -n "$camera_usage" && "$camera_usage" == "$expected_camera_usage" ]] \
  || fail "camera usage description is missing, empty, or has drifted"
readonly declared_usage_description_keys="$(/usr/bin/python3 -c '
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    info = plistlib.load(stream)
print("\n".join(sorted(
    key for key in info
    if isinstance(key, str) and key.startswith("NS") and key.endswith("UsageDescription")
)))
' "$info_path")" || fail "could not enumerate processed usage-description keys"
[[ "$declared_usage_description_keys" == "NSCameraUsageDescription" ]] \
  || fail "processed app contains an unapproved usage-description key set: ${declared_usage_description_keys:-none}"
readonly privacy_policy_url="$(/usr/libexec/PlistBuddy -c 'Print :GIPrivacyPolicyURL' "$info_path" 2>/dev/null)"
readonly support_url="$(/usr/libexec/PlistBuddy -c 'Print :GISupportURL' "$info_path" 2>/dev/null)"
case "${CONFIGURATION:-}" in
  AppStoreTesting)
    [[ "$privacy_policy_url" == "https://example.invalid/gi-journal/privacy-policy" ]] \
      || fail "AppStoreTesting privacy URL drifted from its non-public test value"
    [[ "$support_url" == "https://example.invalid/gi-journal/support" ]] \
      || fail "AppStoreTesting support URL drifted from its non-public test value"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "unrecorded" ]] \
      || fail "AppStoreTesting source commit must be explicitly unrecorded"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "unrecorded" ]] \
      || fail "AppStoreTesting source tree must be explicitly unrecorded"
    ;;
  PhysicalQualification)
    [[ "$privacy_policy_url" == "https://example.invalid/gi-journal/physical-qualification/privacy-policy" ]] \
      || fail "PhysicalQualification privacy URL drifted from its isolated test value"
    [[ "$support_url" == "https://example.invalid/gi-journal/physical-qualification/support" ]] \
      || fail "PhysicalQualification support URL drifted from its isolated test value"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$build_source_commit" ]] \
      || fail "PhysicalQualification Info.plist is not bound to GI_SOURCE_COMMIT"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$build_source_tree" ]] \
      || fail "PhysicalQualification Info.plist is not bound to GI_SOURCE_TREE"
    ;;
  AppStore)
    for public_url in "$privacy_policy_url" "$support_url"; do
      validate_public_url "$public_url"
    done
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$build_source_commit" ]] \
      || fail "processed Info.plist is not bound to GI_SOURCE_COMMIT"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$build_source_tree" ]] \
      || fail "processed Info.plist is not bound to GI_SOURCE_TREE"
    ;;
esac
for prohibited_key in CFBundleDocumentTypes CFBundleURLTypes UTExportedTypeDeclarations UTImportedTypeDeclarations UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
  ! /usr/libexec/PlistBuddy -c "Print :${prohibited_key}" "$info_path" >/dev/null 2>&1 \
    || fail "public bundle unexpectedly exposes a document, URL, or file-type surface through ${prohibited_key}"
done

[[ -f "$app_privacy_path" ]] || fail "app privacy manifest is missing from the bundle"
[[ -f "$framework_privacy_path" ]] || fail "CLiteRTLM privacy manifest is missing from the framework"
for manifest in "$app_privacy_path" "$framework_privacy_path"; do
  /usr/bin/plutil -lint "$manifest" >/dev/null || fail "invalid privacy manifest at ${manifest}"
  [[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw "$manifest" 2>/dev/null)" == "false" ]] \
    || fail "privacy tracking must be declared false at ${manifest}"
  [[ "$(/usr/bin/plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
    || fail "collected data types must be empty at ${manifest}"
  [[ "$(/usr/bin/plutil -extract NSPrivacyTrackingDomains xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
    || fail "tracking domains must be empty at ${manifest}"
done
validate_privacy_api_entry() {
  local manifest="$1"
  local index="$2"
  local expected_category="$3"
  local expected_reason="$4"
  local entry_path="NSPrivacyAccessedAPITypes.${index}"
  local category reason_count reason
  category="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPIType" raw "$manifest" 2>/dev/null)" \
    || fail "privacy manifest is missing API entry ${index} at ${manifest}"
  [[ "$category" == "$expected_category" ]] \
    || fail "privacy API entry ${index} at ${manifest} is ${category}, expected ${expected_category}"
  reason_count="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons" xml1 -o - "$manifest" \
    | /usr/bin/grep -c '<string>')"
  [[ "$reason_count" == "1" ]] \
    || fail "privacy API entry ${expected_category} at ${manifest} must contain exactly one reason"
  reason="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons.0" raw "$manifest" 2>/dev/null)" \
    || fail "privacy API entry ${expected_category} at ${manifest} has no reason"
  [[ "$reason" == "$expected_reason" ]] \
    || fail "privacy API entry ${expected_category} at ${manifest} uses ${reason}, expected ${expected_reason}"
}

[[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$app_privacy_path" | /usr/bin/grep -c '<dict>')" == "4" ]] \
  || fail "app privacy manifest contains an unreviewed accessed-API declaration"
validate_privacy_api_entry "$app_privacy_path" 0 NSPrivacyAccessedAPICategoryUserDefaults CA92.1
validate_privacy_api_entry "$app_privacy_path" 1 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
validate_privacy_api_entry "$app_privacy_path" 2 NSPrivacyAccessedAPICategoryDiskSpace E174.1
validate_privacy_api_entry "$app_privacy_path" 3 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1
[[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$framework_privacy_path" | /usr/bin/grep -c '<dict>')" == "2" ]] \
  || fail "framework privacy manifest contains an unreviewed accessed-API declaration"
validate_privacy_api_entry "$framework_privacy_path" 0 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
validate_privacy_api_entry "$framework_privacy_path" 1 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1

[[ -f "$assets_path" ]] || fail "compiled asset catalog is missing"
[[ -f "$notices_path" ]] || fail "ThirdPartyNotices.txt is missing from the bundle"
for required_notice in \
  "LiteRT-LM" \
  "2117fc4314670e00047bc8469783f02a68c33f0c" \
  "http://www.apache.org/licenses/LICENSE-2.0" \
  "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"; do
  /usr/bin/grep -Fq "$required_notice" "$notices_path" \
    || fail "ThirdPartyNotices.txt is missing ${required_notice}"
done
if [[ "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
  for required_notice in \
    "gemma-4-E4B-it.litertlm" \
    "28299f30ee4d43294517a4ac93abd6163412f07f" \
    "$expected_model_sha256" \
    "https://ai.google.dev/gemma/prohibited_use_policy"; do
    /usr/bin/grep -Fq "$required_notice" "$notices_path" \
      || fail "ThirdPartyNotices.txt is missing ${required_notice}"
  done
fi
[[ -f "$icon_source" ]] || fail "1024-point AppIcon source is missing"
[[ "$(/usr/bin/sips -g pixelWidth "$icon_source" | /usr/bin/awk '/pixelWidth/ { print $2 }')" == "1024" ]] \
  || fail "AppIcon width is not 1024 pixels"
[[ "$(/usr/bin/sips -g pixelHeight "$icon_source" | /usr/bin/awk '/pixelHeight/ { print $2 }')" == "1024" ]] \
  || fail "AppIcon height is not 1024 pixels"

readonly compiled_asset_catalog="$(/usr/bin/assetutil -I "$assets_path")" \
  || fail "could not inspect the compiled asset catalog"
print -rn -- "$compiled_asset_catalog" | /usr/bin/python3 -c '
import json
import sys

assets = json.load(sys.stdin)
icon_images = [asset for asset in assets if asset.get("AssetType") == "Icon Image"]
multi_images = [
    asset for asset in assets
    if asset.get("AssetType") == "MultiSized Image" and asset.get("Name") == "AppIcon"
]
valid_icon = (
    len(icon_images) == 1
    and icon_images[0].get("Name") == "AppIcon"
    and icon_images[0].get("Idiom") == "phone"
    and icon_images[0].get("PixelWidth") == 1024
    and icon_images[0].get("PixelHeight") == 1024
    and icon_images[0].get("Scale") == 1
    and icon_images[0].get("Opaque") is True
)
valid_multi_image = (
    len(multi_images) == 1
    and multi_images[0].get("Name") == "AppIcon"
    and multi_images[0].get("Idiom") == "phone"
    and multi_images[0].get("Sizes") == ["1024x1024 index:1 idiom:phone"]
)
if not (valid_icon and valid_multi_image):
    raise SystemExit(1)
' || fail "compiled asset catalog does not contain exactly the reviewed opaque iPhone AppIcon renditions"

for fixture in \
  synthetic-brown-clay.svg.png \
  synthetic-green-clay.svg.png \
  synthetic-control-geometric.svg.png; do
  [[ ! -e "${app_path}/${fixture}" ]] || fail "synthetic fixture leaked into AppStore: ${fixture}"
done
readonly evaluation_resource_leak="$(/usr/bin/find "$app_path" -type f \( \
  -name 'h??-*.jpg' -o \
  -name 't??-*.jpg' -o \
  -name 'bv??-*.jpg' -o \
  -name 'tuning-v3-manifest.json' \
  -o -name 'blind-validation-v1-manifest.json' \
  -o -name 'AUTHORING_RECEIPT.md' \
\) -print -quit)"
[[ -z "$evaluation_resource_leak" ]] \
  || fail "evaluation-only resource leaked into AppStore: ${evaluation_resource_leak:t}"

# The public bundle is intentionally small and closed.  Reject renamed evaluation
# assets and any newly embedded payload, not just the known diagnostic filenames.
# Signature and provisioning files are optional here because this gate also runs on
# unsigned build products before archive signing.
validate_reviewed_bundle_file_set() {
  local bundled_item relative_path
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    [[ ! -L "$bundled_item" ]] || fail "bundle contains a symlink: ${relative_path}"
    case "$relative_path" in
      AppIcon60x60@2x.png|AppIcon76x76@2x~ipad.png|Assets.car|GITimeline|Info.plist|PkgInfo|PrivacyInfo.xcprivacy|ThirdPartyNotices.txt|embedded.mobileprovision|_CodeSignature/CodeResources|Frameworks/CLiteRTLM.framework/CLiteRTLM|Frameworks/CLiteRTLM.framework/Info.plist|Frameworks/CLiteRTLM.framework/PrivacyInfo.xcprivacy|Frameworks/CLiteRTLM.framework/_CodeSignature/CodeResources) ;;
      EmbeddedModels/gemma-4-E4B-it.litertlm|EmbeddedModels/gemma-4-E4B-it.receipt)
        [[ "${CONFIGURATION:-}" == "PhysicalQualification" ]] \
          || fail "model payload is present outside PhysicalQualification: ${relative_path}"
        ;;
      Frameworks/GITimelineCore_*_PackageProduct.framework/GITimelineCore_*_PackageProduct|Frameworks/GITimelineCore_*_PackageProduct.framework/Info.plist|Frameworks/GITimelineCore_*_PackageProduct.framework/_CodeSignature/CodeResources|Frameworks/Testing.framework/Info.plist|Frameworks/Testing.framework/Testing|Frameworks/Testing.framework/version.plist|Frameworks/Testing.framework/_CodeSignature/CodeResources|Frameworks/XCTAutomationSupport.framework/Info.plist|Frameworks/XCTAutomationSupport.framework/XCTAutomationSupport|Frameworks/XCTAutomationSupport.framework/version.plist|Frameworks/XCTAutomationSupport.framework/_CodeSignature/CodeResources|Frameworks/XCTest.framework/Info.plist|Frameworks/XCTest.framework/XCTest|Frameworks/XCTest.framework/version.plist|Frameworks/XCTest.framework/_CodeSignature/CodeResources|Frameworks/XCTestCore.framework/Info.plist|Frameworks/XCTestCore.framework/XCTestCore|Frameworks/XCTestCore.framework/version.plist|Frameworks/XCTestCore.framework/_CodeSignature/CodeResources|Frameworks/XCTestSupport.framework/Info.plist|Frameworks/XCTestSupport.framework/XCTestSupport|Frameworks/XCTestSupport.framework/version.plist|Frameworks/XCTestSupport.framework/_CodeSignature/CodeResources|Frameworks/XCUIAutomation.framework/Info.plist|Frameworks/XCUIAutomation.framework/XCUIAutomation|Frameworks/XCUIAutomation.framework/version.plist|Frameworks/XCUIAutomation.framework/_CodeSignature/CodeResources|Frameworks/XCUnit.framework/Info.plist|Frameworks/XCUnit.framework/XCUnit|Frameworks/XCUnit.framework/version.plist|Frameworks/XCUnit.framework/_CodeSignature/CodeResources|Frameworks/libXCTestBundleInject.dylib|Frameworks/libXCTestSwiftSupport.dylib)
        [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
          || fail "test-only payload is present outside AppStoreTesting: ${relative_path}"
        ;;
      PlugIns/GITimelineTests.xctest/*|PlugIns/GITimelineTests.xctest.dSYM/*)
        [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
          || fail "unit-test payload is present outside AppStoreTesting: ${relative_path}"
        ;;
      *) fail "bundle contains an unreviewed file: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" \( -type f -o -type l \) -print0)
}
validate_reviewed_bundle_file_set

validate_embedded_framework_set() {
  local framework framework_name
  while IFS= read -r -d $'\0' framework; do
    framework_name="${framework:t}"
    case "$framework_name" in
      CLiteRTLM.framework) ;;
      GITimelineCore_*_PackageProduct.framework|Testing.framework|XCTAutomationSupport.framework|XCTest.framework|XCTestCore.framework|XCTestSupport.framework|XCUIAutomation.framework|XCUnit.framework)
        [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
          || fail "test-only embedded framework is present outside AppStoreTesting: ${framework_name}"
        ;;
      *) fail "bundle contains an unreviewed embedded framework: ${framework_name}" ;;
    esac
  done < <(/usr/bin/find "${app_path}/Frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' -print0)
}
validate_embedded_framework_set

[[ -f "$executable_path" ]] || fail "production executable is missing"
[[ -f "$framework_executable_path" ]] || fail "CLiteRTLM executable is missing"
[[ -f "$framework_info_path" ]] || fail "CLiteRTLM Info.plist is missing"
[[ "$(/usr/bin/stat -f '%Lp' "$executable_path")" == "755" ]] \
  || fail "production executable is not mode 0755"
[[ "$(/usr/bin/stat -f '%Lp' "$framework_executable_path")" == "755" ]] \
  || fail "CLiteRTLM executable is not mode 0755"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$framework_info_path")" == "com.google.odml.litertlm.CLiteRTLM" ]] \
  || fail "CLiteRTLM bundle identifier drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework_info_path")" == "CLiteRTLM" ]] \
  || fail "CLiteRTLM executable name drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$framework_info_path")" == "FMWK" ]] \
  || fail "CLiteRTLM package type drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$framework_info_path" 2>/dev/null)" == "$expected_supported_platform" ]] \
  || fail "CLiteRTLM platform is not ${expected_supported_platform}"
! /usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:1' "$framework_info_path" >/dev/null 2>&1 \
  || fail "CLiteRTLM declares an unreviewed second platform"
validate_macho_dependency_set() {
  local executable="$1"
  local dependency_role="$2"
  local dependency dependency_dump
  dependency_dump="$(/usr/bin/otool -L "$executable" | /usr/bin/awk 'NR > 1 { print $1 }')" \
    || fail "could not inspect ${dependency_role} direct dependencies"
  [[ -n "$dependency_dump" ]] || fail "${dependency_role} executable has no inspectable direct dependencies"
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    if [[ "$dependency_role" == "app" ]]; then
      case "$dependency" in
        @rpath/CLiteRTLM.framework/CLiteRTLM) ;;
        @rpath/GITimelineCore_*_PackageProduct.framework/GITimelineCore_*_PackageProduct)
          [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
            || fail "test-only app dependency is present outside AppStoreTesting: ${dependency}"
          ;;
        /System/Library/Frameworks/Foundation.framework/Foundation|/usr/lib/libobjc.A.dylib|/usr/lib/libSystem.B.dylib|/System/Library/Frameworks/Combine.framework/Combine|/System/Library/Frameworks/CoreData.framework/CoreData|/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation|/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics|/System/Library/Frameworks/CoreText.framework/CoreText|/System/Library/Frameworks/CoreTransferable.framework/CoreTransferable|/System/Library/Frameworks/CryptoKit.framework/CryptoKit|/System/Library/Frameworks/ImageIO.framework/ImageIO|/System/Library/Frameworks/PDFKit.framework/PDFKit|/System/Library/Frameworks/PhotosUI.framework/PhotosUI|/System/Library/Frameworks/SwiftData.framework/SwiftData|/System/Library/Frameworks/SwiftUI.framework/SwiftUI|/System/Library/Frameworks/UIKit.framework/UIKit|/System/Library/Frameworks/_PhotosUI_SwiftUI.framework/_PhotosUI_SwiftUI|/System/Library/Frameworks/_SwiftData_SwiftUI.framework/_SwiftData_SwiftUI|/usr/lib/libc++.1.dylib|/usr/lib/swift/libswiftAVFoundation.dylib|/usr/lib/swift/libswiftCore.dylib|/usr/lib/swift/libswiftCoreAudio.dylib|/usr/lib/swift/libswiftCoreFoundation.dylib|/usr/lib/swift/libswiftCoreImage.dylib|/usr/lib/swift/libswiftCoreLocation.dylib|/usr/lib/swift/libswiftCoreMIDI.dylib|/usr/lib/swift/libswiftCoreMedia.dylib|/usr/lib/swift/libswiftDarwin.dylib|/usr/lib/swift/libswiftDispatch.dylib|/usr/lib/swift/libswiftMetal.dylib|/usr/lib/swift/libswiftOSLog.dylib|/usr/lib/swift/libswiftObjectiveC.dylib|/usr/lib/swift/libswiftObservation.dylib|/usr/lib/swift/libswiftQuartzCore.dylib|/usr/lib/swift/libswiftSpatial.dylib|/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib|/usr/lib/swift/libswiftXPC.dylib|/usr/lib/swift/libswift_Concurrency.dylib|/usr/lib/swift/libswiftos.dylib|/usr/lib/swift/libswiftsimd.dylib|/usr/lib/swift/libswiftCoreGraphics.dylib) ;;
        *) fail "app executable contains an unreviewed direct dependency: ${dependency}" ;;
      esac
    else
      case "$dependency" in
        @rpath/CLiteRTLM.framework/CLiteRTLM|/System/Library/Frameworks/AVFoundation.framework/AVFoundation|/System/Library/Frameworks/AVFAudio.framework/AVFAudio|/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox|/System/Library/Frameworks/CoreVideo.framework/CoreVideo|/System/Library/Frameworks/MetalKit.framework/MetalKit|/System/Library/Frameworks/OpenGLES.framework/OpenGLES|/usr/lib/libSystem.B.dylib|/System/Library/Frameworks/Metal.framework/Metal|/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation|/usr/lib/libobjc.A.dylib|/usr/lib/libc++.1.dylib|/System/Library/Frameworks/Foundation.framework/Foundation) ;;
        *) fail "CLiteRTLM executable contains an unreviewed direct dependency: ${dependency}" ;;
      esac
    fi
  done <<< "$dependency_dump"
}
validate_macho_dependency_set "$executable_path" app
validate_macho_dependency_set "$framework_executable_path" framework
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$executable_path" "$expected_macho_platform" "17.0" \
  || fail "production executable Mach-O platform/minimum OS drifted"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$framework_executable_path" "$expected_macho_platform" "15.0" \
  || fail "CLiteRTLM Mach-O platform/minimum OS drifted"
readonly framework_uuid="$(/usr/bin/dwarfdump --uuid "$framework_executable_path" \
  | /usr/bin/awk '$1 == "UUID:" && !printed { print $2; printed=1 } $2 == "UUID:" && !printed { print $3; printed=1 }')"
[[ "$framework_uuid" == "$expected_framework_uuid" ]] \
  || fail "CLiteRTLM arm64 UUID ${framework_uuid:-unavailable} does not match the reviewed artifact"
readonly framework_linkedit_fileoff="$(/usr/bin/otool -l "$framework_executable_path" \
  | /usr/bin/awk '/segname __LINKEDIT/ { found=1 } found && !printed && $1 == "fileoff" { print $2; printed=1 }')"
[[ "$framework_linkedit_fileoff" == "$expected_framework_linkedit_fileoff" ]] \
  || fail "CLiteRTLM __LINKEDIT file offset ${framework_linkedit_fileoff:-unavailable} does not match the reviewed artifact"
readonly framework_normalized_sha256="$(/usr/bin/python3 "$script_directory/NormalizedMachOExecutableHash.py" "$framework_executable_path" "$framework_linkedit_fileoff")" \
  || fail "could not normalize/hash the CLiteRTLM executable"
[[ "$framework_normalized_sha256" == "$expected_framework_normalized_sha256" ]] \
  || fail "CLiteRTLM signing-normalized Mach-O SHA-256 does not match the reviewed artifact"
typeset -i app_text_segment_bytes
typeset -i framework_text_segment_bytes
app_text_segment_bytes="$(/usr/bin/size -m "$executable_path" \
  | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
framework_text_segment_bytes="$(/usr/bin/size -m "$framework_executable_path" \
  | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
(( app_text_segment_bytes > 0 )) || fail "could not measure the app executable __TEXT segment"
(( framework_text_segment_bytes > 0 )) || fail "could not measure the CLiteRTLM __TEXT segment"
(( app_text_segment_bytes < maximum_text_segment_bytes )) \
  || fail "app executable __TEXT bytes ${app_text_segment_bytes} reach or exceed ${maximum_text_segment_bytes}"
(( framework_text_segment_bytes < maximum_text_segment_bytes )) \
  || fail "CLiteRTLM __TEXT bytes ${framework_text_segment_bytes} reach or exceed ${maximum_text_segment_bytes}"
readonly total_text_segment_bytes=$(( app_text_segment_bytes + framework_text_segment_bytes ))
(( total_text_segment_bytes < maximum_text_segment_bytes )) \
  || fail "combined app and CLiteRTLM __TEXT bytes ${total_text_segment_bytes} reach or exceed ${maximum_text_segment_bytes}"
readonly strings_dump="$(/usr/bin/mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/GITimeline-AppStore-strings.XXXXXX")"
readonly entitlements_dump="$(/usr/bin/mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/GITimeline-AppStore-entitlements.XXXXXX")"
cleanup() {
  /bin/rm -f "$strings_dump" "$entitlements_dump"
}
trap cleanup EXIT

/usr/bin/strings -a "$executable_path" > "$strings_dump" \
  || fail "could not inspect production executable strings"
for prohibited_marker in \
  "--show-developer-tools" \
  "--ui-test-ephemeral-store" \
  "--run-overnight-gemma-smoke" \
  "--run-embedded-gemma-smoke" \
  "--internal-app-store-raw-image-v1" \
  "--diagnose-app-store-raw-image-v1-gpu-main-cpu-vision70-ab" \
  "diagnostic-app-store-raw-image-v1-gpu-main-cpu-vision70" \
  "--diagnose-app-store-raw-image-v1-preparation" \
  "--diagnose-app-store-raw-image-v1-preparation-fresh-cache" \
  "--diagnose-app-store-raw-image-v1-preparation-caches-root" \
  "--diagnose-app-store-raw-image-v1-direct-image-data" \
  "--diagnose-app-store-raw-image-v1-sync-send-ab" \
  "conversation_send_message_sync_v1" \
  "sync_send_start" \
  "sync_cancel_requested" \
  "sync_quarantined" \
  "fresh_isolated_diagnostic_cache" \
  "fresh_caches_root_diagnostic_cache" \
  "InternalRawImageV1PreparationCache" \
  "InternalRawImageV1PreparationCaches" \
  "--run-embedded-gemma-normal-flow" \
  "--verify-embedded-gemma-normal-flow" \
  "--run-physical-raw-image" \
  "--run-photo-evaluation-derived-map-iphone" \
  "--run-photo-evaluation-raw-image-simulator" \
  "--run-photo-tuning-derived-map-v3" \
  "--run-photo-blind-validation-v3" \
  "--run-raw-photo-v12-tuning-simulator-baseline" \
  "--run-raw-photo-v12-tuning-simulator-candidate" \
  "--raw-photo-v12-tuning-fixture-" \
  "GI_JOURNAL_UI_EVIDENCE_SEEDED" \
  "OVERNIGHT_GEMMA_SMOKE_PASS" \
  "EMBEDDED_GEMMA_SMOKE_PASS" \
  "EMBEDDED_GEMMA_NORMAL_FLOW_PASS" \
  "EMBEDDED_GEMMA_RELAUNCH_PASS" \
  "EMBEDDED_GEMMA_COMPLETION_FAIL" \
  "APP_STORE_RAW_IMAGE_V1_PREPARATION" \
  "PHOTO_SUGGESTION_EVALUATION_PASS" \
  "PHOTO_TUNING_V3_PASS" \
  "PHOTO_TUNING_V3_FAIL" \
  "PHOTO_TUNING_V3_RUN_COMPLETE" \
  "physical-cpu-local-pixel-bridge-extractor-v3-tuning" \
  "gi-local-pixel-bridge-v3-tuning" \
  "DERIVED_MAP_V3_TUNING_ONLY" \
  "TUNING_V3_ENGINEERING_METRICS_RECORDED" \
  "TUNING_V3_RUN_INCOMPLETE" \
  "PHOTO_BLIND_VALIDATION_V1_RUN_COMPLETE" \
  "PHOTO_BLIND_VALIDATION_V1_FAIL" \
  "physical-cpu-local-pixel-bridge-extractor-v3-blind-validation-v1" \
  "gi-local-pixel-bridge-v3-blind-validation-v1" \
  "DERIVED_MAP_V3_BLIND_VALIDATION_V1_ONE_SHOT" \
  "BLIND_VALIDATION_V1_ELIGIBLE_FOR_MANUAL_PROMOTION_REVIEW" \
  "BLIND_VALIDATION_V1_CANDIDATE_REJECTED" \
  "BLIND_VALIDATION_V1_RUN_INCOMPLETE" \
  "RAW_PHOTO_V12_TUNING" \
  "RawPhotoV12TuningV1" \
  "raw-photo-v12-subject-gate-tuning-v1" \
  "RawPhotoV12TuningAttemptLedgerV1" \
  "holdout_manifest_access" \
  "isolation_attested" \
  "00d8e8bc11b8ba83d4cb624bc69e45542b7aae0420a45b17d66e52232d34e7bc" \
  "diagnostic-app-store-raw-image-v1.2-subject-gate-tuning-v1" \
  "gi-photo-v1.2-subject-gate-tuning-v1" \
  "GIJournalBlindValidationV1"; do
  ! /usr/bin/grep -Fq -- "$prohibited_marker" "$strings_dump" \
    || fail "production executable contains prohibited marker ${prohibited_marker}"
done
for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
  ! /usr/bin/grep -Fqi -- "$prohibited_marker" "$strings_dump" \
    || fail "production executable contains retired recovery marker ${prohibited_marker}"
done

if /usr/bin/codesign -d "$app_path" >/dev/null 2>&1; then
  /usr/bin/codesign -d --entitlements :- "$app_path" > "$entitlements_dump" 2>/dev/null \
    || fail "could not inspect signed app entitlements"
  if /usr/bin/plutil -lint "$entitlements_dump" >/dev/null 2>&1; then
    readonly get_task_allow="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements_dump" 2>/dev/null || true)"
    if [[ "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
      [[ -n "$physical_team_id" ]] \
        || fail "EXPECTED_PHYSICAL_TEAM_ID is required for signed PhysicalQualification validation"
      [[ "$get_task_allow" == "true" ]] \
        || fail "signed PhysicalQualification app must use device-development signing"
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$entitlements_dump" 2>/dev/null || true)" \
        == "${physical_team_id}.com.omairmkhan.GITimeline.qualification" ]] \
        || fail "signed PhysicalQualification app identifier entitlement drifted"
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements_dump" 2>/dev/null || true)" \
        == "$physical_team_id" ]] \
        || fail "signed PhysicalQualification team entitlement drifted"
    else
      [[ "$get_task_allow" != "true" ]] \
        || fail "signed AppStore app has get-task-allow entitlement"
    fi
  fi
fi

typeset -i total_uncompressed_bytes=0
while IFS= read -r -d $'\0' bundled_file; do
  (( total_uncompressed_bytes += $(/usr/bin/stat -f '%z' "$bundled_file") ))
done < <(/usr/bin/find "$app_path" -type f -print0)
(( total_uncompressed_bytes < maximum_uncompressed_bytes )) \
  || fail "uncompressed regular-file bytes ${total_uncompressed_bytes} reach or exceed ${maximum_uncompressed_bytes}"
readonly size_safety_margin=$(( maximum_uncompressed_bytes - total_uncompressed_bytes ))

print -r -- "status=validated" > "$stamp_path"
print -- "validated AppStore package inputs and bundle contents; uncompressed_regular_file_bytes=${total_uncompressed_bytes}; safety_margin_bytes=${size_safety_margin}; app_text_segment_bytes=${app_text_segment_bytes}; framework_text_segment_bytes=${framework_text_segment_bytes}; total_text_segment_bytes=${total_text_segment_bytes}"
