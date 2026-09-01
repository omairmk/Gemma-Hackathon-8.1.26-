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

validate_retired_runtime_payload_absence() {
  local app_bundle_path="$1"
  local prohibited_payload
  prohibited_payload="$(/usr/bin/find "$app_bundle_path" \( -type f -o -type l -o -type d \) \( \
    -iname '*litert*' -o -iname '*gemma*' -o -iname '*qwen*' -o -iname '*mlx*' \
    -o -name '*.litertlm' -o -name '*.safetensors' -o -name '*.gguf' \
  \) -print -quit)"
  [[ -z "$prohibited_payload" ]] \
    || fail "retired generative runtime/model payload is present: ${prohibited_payload#$app_bundle_path/}"
  [[ ! -e "${app_bundle_path}/EmbeddedModels" && ! -L "${app_bundle_path}/EmbeddedModels" ]] \
    || fail "bundle contains a retired EmbeddedModels directory"
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
    [[ "$(normalized_condition_set "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}")" == "APPSTORE_RELEASE MANUAL_FALLBACK_RELEASE" ]] \
      || fail "PhysicalQualification must compile the same reviewed manual-fallback source lane"
    ;;
  *)
    [[ "$enabled" != "YES" ]] \
      || fail "package validation may be enabled only for AppStore, AppStoreTesting, or PhysicalQualification"
    /bin/mkdir -p "${stamp_path:h}"
    print -r -- "status=not_app_store_configuration" > "$stamp_path"
    exit 0
    ;;
esac

[[ "$enabled" == "YES" ]] || fail "${CONFIGURATION} package validation cannot be disabled"

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

readonly build_source_commit="${GI_SOURCE_COMMIT:-}"
readonly build_source_tree="${GI_SOURCE_TREE:-}"
readonly app_path="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${WRAPPER_NAME:?WRAPPER_NAME is required}"
readonly info_path="${app_path}/Info.plist"
readonly app_privacy_path="${app_path}/PrivacyInfo.xcprivacy"
readonly assets_path="${app_path}/Assets.car"
readonly notices_path="${app_path}/ThirdPartyNotices.txt"
readonly icon_source="${SRCROOT:?SRCROOT is required}/GITimeline/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
readonly executable_path="${app_path}/${EXECUTABLE_NAME:?EXECUTABLE_NAME is required}"
readonly maximum_uncompressed_bytes=750000000
readonly maximum_text_segment_bytes=250000000

[[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" == "$expected_bundle_id" ]] || fail "bundle identifier is not reviewed"
[[ "${MARKETING_VERSION:-}" == "$expected_marketing_version" ]] \
  || fail "marketing version must be ${expected_marketing_version}"
[[ "${CURRENT_PROJECT_VERSION:-}" == "$expected_build_number" ]] \
  || fail "build number must be ${expected_build_number}"

if [[ "${CONFIGURATION:-}" == "AppStore" || "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
  [[ ${#build_source_commit} == 40 && "$build_source_commit" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} requires a recorded GI_SOURCE_COMMIT"
  [[ ${#build_source_tree} == 40 && "$build_source_tree" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} requires a recorded GI_SOURCE_TREE"
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
[[ "$(/usr/bin/plutil -extract UIDeviceFamily raw -expect array "$info_path" 2>/dev/null)" == "1" ]] \
  || fail "processed app must declare exactly one device family"
[[ "$(/usr/bin/plutil -extract UIDeviceFamily.0 raw -expect integer "$info_path" 2>/dev/null)" == "1" ]] \
  || fail "processed app is not declared for iPhone"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$info_path" 2>/dev/null)" == "$expected_supported_platform" ]] \
  || fail "processed app platform is not ${expected_supported_platform}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_path")" == "false" ]] \
  || fail "non-exempt encryption declaration is not false"
readonly camera_usage="$(/usr/bin/plutil -extract NSCameraUsageDescription raw -expect string "$info_path" 2>/dev/null)"
[[ "$camera_usage" == "$expected_camera_usage" ]] || fail "camera usage description drifted"
readonly declared_usage_description_keys="$(/usr/bin/python3 -c '
import plistlib, sys
with open(sys.argv[1], "rb") as stream:
    info = plistlib.load(stream)
print("\n".join(sorted(
    key for key in info
    if isinstance(key, str) and key.startswith("NS") and key.endswith("UsageDescription")
)))
' "$info_path")" || fail "could not enumerate processed usage-description keys"
[[ "$declared_usage_description_keys" == "NSCameraUsageDescription" ]] \
  || fail "processed app contains an unapproved usage-description key set"

readonly privacy_policy_url="$(/usr/libexec/PlistBuddy -c 'Print :GIPrivacyPolicyURL' "$info_path" 2>/dev/null)"
readonly support_url="$(/usr/libexec/PlistBuddy -c 'Print :GISupportURL' "$info_path" 2>/dev/null)"
case "${CONFIGURATION:-}" in
  AppStoreTesting)
    [[ "$privacy_policy_url" == "https://example.invalid/gi-journal/privacy-policy" ]] \
      || fail "AppStoreTesting privacy URL drifted"
    [[ "$support_url" == "https://example.invalid/gi-journal/support" ]] \
      || fail "AppStoreTesting support URL drifted"
    ;;
  PhysicalQualification)
    [[ "$privacy_policy_url" == "https://example.invalid/gi-journal/physical-qualification/privacy-policy" ]] \
      || fail "PhysicalQualification privacy URL drifted"
    [[ "$support_url" == "https://example.invalid/gi-journal/physical-qualification/support" ]] \
      || fail "PhysicalQualification support URL drifted"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$build_source_commit" ]] \
      || fail "PhysicalQualification Info.plist is not bound to GI_SOURCE_COMMIT"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$build_source_tree" ]] \
      || fail "PhysicalQualification Info.plist is not bound to GI_SOURCE_TREE"
    ;;
  AppStore)
    validate_public_url "$privacy_policy_url"
    validate_public_url "$support_url"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$build_source_commit" ]] \
      || fail "processed Info.plist is not bound to GI_SOURCE_COMMIT"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$build_source_tree" ]] \
      || fail "processed Info.plist is not bound to GI_SOURCE_TREE"
    ;;
esac

for prohibited_key in CFBundleDocumentTypes CFBundleURLTypes UTExportedTypeDeclarations UTImportedTypeDeclarations UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
  ! /usr/libexec/PlistBuddy -c "Print :${prohibited_key}" "$info_path" >/dev/null 2>&1 \
    || fail "public bundle unexpectedly exposes ${prohibited_key}"
done

[[ -f "$app_privacy_path" ]] || fail "app privacy manifest is missing"
/usr/bin/plutil -lint "$app_privacy_path" >/dev/null || fail "app privacy manifest is invalid"
[[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw "$app_privacy_path" 2>/dev/null)" == "false" ]] \
  || fail "privacy tracking must be false"
[[ "$(/usr/bin/plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$app_privacy_path" 2>/dev/null)" == *"<array/>"* ]] \
  || fail "collected data types must be empty"
[[ "$(/usr/bin/plutil -extract NSPrivacyTrackingDomains xml1 -o - "$app_privacy_path" 2>/dev/null)" == *"<array/>"* ]] \
  || fail "tracking domains must be empty"
[[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$app_privacy_path" | /usr/bin/grep -c '<dict>')" == "4" ]] \
  || fail "app privacy manifest contains an unreviewed accessed-API declaration"
validate_privacy_api_entry "$app_privacy_path" 0 NSPrivacyAccessedAPICategoryUserDefaults CA92.1
validate_privacy_api_entry "$app_privacy_path" 1 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
validate_privacy_api_entry "$app_privacy_path" 2 NSPrivacyAccessedAPICategoryDiskSpace E174.1
validate_privacy_api_entry "$app_privacy_path" 3 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1

[[ -f "$assets_path" ]] || fail "compiled asset catalog is missing"
[[ -f "$notices_path" ]] || fail "ThirdPartyNotices.txt is missing"
/usr/bin/grep -Fq "No third-party model or inference runtime is bundled" "$notices_path" \
  || fail "ThirdPartyNotices.txt does not describe the reviewed dependency-free runtime"
for prohibited_notice in LiteRT Gemma Qwen MLX; do
  ! /usr/bin/grep -Fq "$prohibited_notice" "$notices_path" \
    || fail "ThirdPartyNotices.txt contains retired runtime notice ${prohibited_notice}"
done

[[ -f "$icon_source" ]] || fail "1024-point AppIcon source is missing"
[[ "$(/usr/bin/sips -g pixelWidth "$icon_source" | /usr/bin/awk '/pixelWidth/ { print $2 }')" == "1024" ]] \
  || fail "AppIcon width is not 1024 pixels"
[[ "$(/usr/bin/sips -g pixelHeight "$icon_source" | /usr/bin/awk '/pixelHeight/ { print $2 }')" == "1024" ]] \
  || fail "AppIcon height is not 1024 pixels"

validate_retired_runtime_payload_absence "$app_path"

if [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]]; then
  readonly evaluation_resource_leak="$(/usr/bin/find "$app_path" \
    -path "${app_path}/PlugIns" -prune -o \
    -type f \( \
      -name 'h??-*.jpg' -o -name 't??-*.jpg' -o -name 'bv??-*.jpg' \
      -o -name '*manifest.json' -o -name 'AUTHORING_RECEIPT.md' \
    \) -print -quit)"
else
  readonly evaluation_resource_leak="$(/usr/bin/find "$app_path" -type f \( \
    -name 'h??-*.jpg' -o -name 't??-*.jpg' -o -name 'bv??-*.jpg' \
    -o -name '*manifest.json' -o -name 'AUTHORING_RECEIPT.md' \
  \) -print -quit)"
fi
[[ -z "$evaluation_resource_leak" ]] \
  || fail "evaluation-only resource leaked into AppStore: ${evaluation_resource_leak:t}"

validate_reviewed_bundle_file_set() {
  local bundled_item relative_path
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    [[ ! -L "$bundled_item" ]] || fail "bundle contains a symlink: ${relative_path}"
    case "$relative_path" in
      AppIcon60x60@2x.png|AppIcon76x76@2x~ipad.png|Assets.car|GITimeline|Info.plist|PkgInfo|PrivacyInfo.xcprivacy|ThirdPartyNotices.txt|embedded.mobileprovision|_CodeSignature/CodeResources) ;;
      Frameworks/GITimelineCore_*_PackageProduct.framework/*|Frameworks/Testing.framework/*|Frameworks/XCTAutomationSupport.framework/*|Frameworks/XCTest.framework/*|Frameworks/XCTestCore.framework/*|Frameworks/XCTestSupport.framework/*|Frameworks/XCUIAutomation.framework/*|Frameworks/XCUnit.framework/*|Frameworks/libXCTestBundleInject.dylib|Frameworks/libXCTestSwiftSupport.dylib|PlugIns/GITimelineTests.xctest/*|PlugIns/GITimelineTests.xctest.dSYM/*)
        [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
          || fail "test-only payload is present outside AppStoreTesting: ${relative_path}"
        ;;
      *) fail "bundle contains an unreviewed file: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" \( -type f -o -type l \) -print0)
}
validate_reviewed_bundle_file_set

if [[ -d "${app_path}/Frameworks" ]]; then
  while IFS= read -r -d $'\0' framework; do
    case "${framework:t}" in
      GITimelineCore_*_PackageProduct.framework|Testing.framework|XCTAutomationSupport.framework|XCTest.framework|XCTestCore.framework|XCTestSupport.framework|XCUIAutomation.framework|XCUnit.framework)
        [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]] \
          || fail "test-only framework is present outside AppStoreTesting: ${framework:t}"
        ;;
      *) fail "bundle contains an unreviewed embedded framework: ${framework:t}" ;;
    esac
  done < <(/usr/bin/find "${app_path}/Frameworks" -mindepth 1 -maxdepth 1 -type d -name '*.framework' -print0)
fi

[[ -f "$executable_path" ]] || fail "production executable is missing"
[[ "$(/usr/bin/stat -f '%Lp' "$executable_path")" == "755" ]] \
  || fail "production executable is not mode 0755"
if [[ "${CONFIGURATION:-}" == "AppStoreTesting" ]]; then
  readonly executable_archs="$(/usr/bin/lipo -archs "$executable_path")" \
    || fail "could not inspect AppStoreTesting executable architectures"
  if [[ "$executable_archs" == "arm64" ]]; then
    /usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$executable_path" "$expected_macho_platform" "17.0" \
      || fail "production executable arm64 simulator Mach-O platform/minimum OS drifted"
  elif [[ " ${executable_archs} " == *" arm64 "* ]]; then
    readonly thin_executable_path="$(/usr/bin/mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/GITimeline-AppStoreTesting-arm64.XXXXXX")"
    /usr/bin/lipo "$executable_path" -thin arm64 -output "$thin_executable_path" \
      || fail "could not isolate the arm64 simulator executable slice"
    /usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$thin_executable_path" "$expected_macho_platform" "17.0" \
      || fail "production executable arm64 simulator Mach-O platform/minimum OS drifted"
    /bin/rm -f "$thin_executable_path"
  else
    fail "AppStoreTesting executable lacks arm64 simulator slice: ${executable_archs}"
  fi
else
  /usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$executable_path" "$expected_macho_platform" "17.0" \
    || fail "production executable Mach-O platform/minimum OS drifted"
fi

readonly dependency_dump="$(/usr/bin/otool -L "$executable_path" | /usr/bin/awk 'NR > 1 { print $1 }')" \
  || fail "could not inspect app dependencies"
for prohibited_dependency in CLiteRT LiteRT Gemma Qwen MLX; do
  ! print -r -- "$dependency_dump" | /usr/bin/grep -Fiq "$prohibited_dependency" \
    || fail "app executable links retired runtime ${prohibited_dependency}"
done

typeset -i app_text_segment_bytes
app_text_segment_bytes="$(/usr/bin/size -m "$executable_path" \
  | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
(( app_text_segment_bytes > 0 )) || fail "could not measure the app executable __TEXT segment"
(( app_text_segment_bytes < maximum_text_segment_bytes )) \
  || fail "app executable __TEXT bytes ${app_text_segment_bytes} reach or exceed ${maximum_text_segment_bytes}"

readonly strings_dump="$(/usr/bin/mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/GITimeline-AppStore-strings.XXXXXX")"
readonly entitlements_dump="$(/usr/bin/mktemp "${TEMP_DIR:-${TMPDIR:-/tmp}}/GITimeline-AppStore-entitlements.XXXXXX")"
cleanup() {
  /bin/rm -f "$strings_dump" "$entitlements_dump"
}
trap cleanup EXIT

/usr/bin/strings -a "$executable_path" > "$strings_dump" || fail "could not inspect executable strings"
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
    else
      [[ "$get_task_allow" != "true" ]] || fail "signed AppStore app has get-task-allow entitlement"
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

/bin/mkdir -p "${stamp_path:h}"
print -r -- "status=validated" > "$stamp_path"
print -- "validated Apple-framework-only AppStore package; uncompressed_regular_file_bytes=${total_uncompressed_bytes}; safety_margin_bytes=${size_safety_margin}; app_text_segment_bytes=${app_text_segment_bytes}"
