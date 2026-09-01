#!/bin/zsh

set -euo pipefail

readonly repo_root="${0:A:h:h}"
readonly project_file="${repo_root}/GITimeline.xcodeproj/project.pbxproj"
readonly package_lock="${repo_root}/GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly app_info="${repo_root}/GITimeline/Info-AppStore.plist"
readonly development_info="${repo_root}/GITimeline/Info.plist"
readonly app_manifest="${repo_root}/GITimeline/PrivacyInfo.xcprivacy"
readonly appstore_build_validator="${repo_root}/Scripts/ValidateAppStoreBuild.sh"
readonly release_plan="${repo_root}/Release/APP_STORE_RELEASE_PLAN.md"
source "${repo_root}/Scripts/RetiredRecoverySurfaceMarkers.zsh"

fail() {
  print -u2 -- "LOCAL_ONLY_SOURCE_VALIDATION: FAIL: $1"
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

configuration_field() {
  local configuration_id="$1"
  local field="$2"
  if [[ "$field" == "name" ]]; then
    /usr/bin/awk -v configuration_id="$configuration_id" '
      $0 ~ "^[[:space:]]*" configuration_id "[[:space:]]+/\\*" {
        value = $0
        sub("^.*?/\\* ", "", value)
        sub(" \\*/ = \\{[[:space:]]*$", "", value)
        print value
        exit
      }
    ' "$project_file"
    return
  fi
  /usr/bin/awk -v configuration_id="$configuration_id" -v field="$field" '
    $0 ~ "^[[:space:]]*" configuration_id "[[:space:]]+/\\*" { in_configuration = 1; next }
    in_configuration && $0 ~ "^[[:space:]]*" field "[[:space:]]*=" {
      value = $0
      sub("^[[:space:]]*" field "[[:space:]]*=[[:space:]]*", "", value)
      sub(";[[:space:]]*$", "", value)
      print value
      exit
    }
    in_configuration && /^[[:space:]]*};/ { exit }
  ' "$project_file"
}

for required_file in \
  "$project_file" \
  "$package_lock" \
  "$app_info" \
  "$development_info" \
  "$app_manifest" \
  "$appstore_build_validator" \
  "$release_plan"; do
  [[ -f "$required_file" && ! -L "$required_file" ]] \
    || fail "required reviewed source is missing or symlinked: ${required_file#$repo_root/}"
done

/usr/bin/plutil -lint "$project_file" "$app_info" "$development_info" "$app_manifest" >/dev/null \
  || fail "a reviewed project/plist file is invalid"

typeset -a configuration_ids
configuration_ids=(
  "${(@f)$(/usr/bin/awk '
    /Build configuration list for PBXNativeTarget "GITimeline"/ { found_target = 1; next }
    found_target && /buildConfigurations = \(/ { in_list = 1; next }
    in_list && /^[[:space:]]*[A-Za-z0-9]+[[:space:]]+\/\*/ {
      identifier = $0
      sub(/^[[:space:]]*/, "", identifier)
      sub(/[[:space:]].*/, "", identifier)
      print identifier
      next
    }
    in_list && /^[[:space:]]*\);/ { exit }
  ' "$project_file")}"
)
(( ${#configuration_ids[@]} > 0 )) || fail "could not locate app-target configurations"

typeset -A expected_conditions expected_bundle_ids
expected_conditions=(
  AppStore "APPSTORE_RELEASE MANUAL_FALLBACK_RELEASE"
  AppStoreTesting "APPSTORE_RELEASE APPSTORE_RELEASE_TESTING MANUAL_FALLBACK_RELEASE"
  PhysicalQualification "APPSTORE_RELEASE MANUAL_FALLBACK_RELEASE"
)
expected_bundle_ids=(
  AppStore com.omairmkhan.GITimeline
  AppStoreTesting com.omairmkhan.GITimeline.appstoretesting
  PhysicalQualification com.omairmkhan.GITimeline.qualification
)
typeset -A seen
for configuration_id in "${configuration_ids[@]}"; do
  configuration_name="$(configuration_field "$configuration_id" name)"
  [[ -n "$configuration_name" ]] || fail "could not identify configuration ${configuration_id}"
  if [[ -n "${expected_conditions[$configuration_name]:-}" ]]; then
    seen[$configuration_name]=1
    [[ "$(configuration_field "$configuration_id" INFOPLIST_FILE)" == '"GITimeline/Info-AppStore.plist"' ]] \
      || fail "${configuration_name} must use Info-AppStore.plist"
    [[ "$(normalized_condition_set "$(configuration_field "$configuration_id" SWIFT_ACTIVE_COMPILATION_CONDITIONS)")" \
      == "${expected_conditions[$configuration_name]}" ]] \
      || fail "${configuration_name} compilation conditions drifted"
    [[ "$(configuration_field "$configuration_id" PRODUCT_BUNDLE_IDENTIFIER)" \
      == "${expected_bundle_ids[$configuration_name]}" ]] \
      || fail "${configuration_name} bundle identifier drifted"
  else
    [[ "$(configuration_field "$configuration_id" INFOPLIST_FILE)" != '"GITimeline/Info-AppStore.plist"' ]] \
      || fail "only reviewed public/device configurations may use Info-AppStore.plist"
  fi
done
for configuration_name in AppStore AppStoreTesting PhysicalQualification; do
  [[ "${seen[$configuration_name]:-0}" == "1" ]] \
    || fail "missing reviewed ${configuration_name} configuration"
done

for prohibited_project_marker in LiteRTLM CLiteRT Gemma Qwen MLX HACKATHON_EMBEDDED_GEMMA INTERNAL_QWEN3_QA; do
  ! /usr/bin/grep -Fqi -- "$prohibited_project_marker" "$project_file" \
    || fail "Xcode project contains retired runtime marker ${prohibited_project_marker}"
done
for prohibited_project_marker in '.litertlm' '.safetensors' '.gguf' EmbeddedModels; do
  ! /usr/bin/grep -Fq -- "$prohibited_project_marker" "$project_file" \
    || fail "Xcode project contains retired payload marker ${prohibited_project_marker}"
done

[[ "$(/usr/bin/plutil -extract pins json -o - "$package_lock")" == "[]" ]] \
  || fail "Package.resolved must contain no remote source-control pins"

/usr/bin/grep -Fq '#if MANUAL_FALLBACK_RELEASE' "${repo_root}/GITimeline/ModelRuntime.swift" \
  || fail "manual-fallback model selection guard is missing"
/usr/bin/grep -Fq 'static var normalFlowSelection: ModelDescriptor?' "${repo_root}/GITimeline/ModelRuntime.swift" \
  || fail "provider-neutral normal-flow selection seam is missing"
/usr/bin/grep -Fq 'inference: UnavailableInferenceService()' "${repo_root}/GITimeline/NewEntryView.swift" \
  || fail "manual-entry fail-closed inference service is missing"
/usr/bin/grep -Fq 'autoAnalysisEnabled: false' "${repo_root}/GITimeline/NewEntryView.swift" \
  || fail "manual fallback does not disable automatic analysis"
/usr/bin/grep -Fq '#if canImport(LiteRTLM)' "${repo_root}/GITimeline/InferenceService.swift" \
  || fail "historical runtime compatibility code is not compile-time isolated"
/usr/bin/grep -Fq 'Shipping compatibility shell for historical coordinator call sites.' "${repo_root}/GITimeline/InferenceService.swift" \
  || fail "runtime-free inference compatibility shell is missing"
[[ "$(/usr/bin/head -n 1 "${repo_root}/GITimeline/Qwen3HybridPhotoSuggestionEngine.swift")" == '#if INTERNAL_QWEN3_QA' ]] \
  || fail "internal Qwen source is not wholly gated from public compilation"

/usr/bin/grep -Fq 'validate_retired_runtime_payload_absence' "$appstore_build_validator" \
  || fail "package validator lacks the retired-runtime payload gate"
/usr/bin/grep -Fq 'No third-party model or inference runtime is bundled' "${repo_root}/GITimeline/ThirdPartyNotices.txt" \
  || fail "bundled notice does not describe the runtime-free package"
/usr/bin/grep -Fq 'The public build does **not** analyze photos' "$release_plan" \
  || fail "release authority does not disclose the manual-first public behavior"

[[ "$(/usr/bin/find "${repo_root}/GITimeline" -name '*.entitlements' -type f -print -quit)" == "" ]] \
  || fail "app source contains an unreviewed entitlements file"
! /usr/bin/grep -Eq 'CODE_SIGN_ENTITLEMENTS|SystemCapabilities|com\.apple\.developer\.|CloudKit|iCloud' "$project_file" \
  || fail "project contains an unreviewed entitlement or cloud capability"
/usr/bin/grep -Fq 'cloudKitDatabase: .none' "${repo_root}/GITimeline/PersistenceSchema.swift" \
  || fail "SwiftData is not explicitly configured without CloudKit"

for plist in "$app_info" "$development_info"; do
  for prohibited_key in CFBundleDocumentTypes CFBundleURLTypes UTExportedTypeDeclarations UTImportedTypeDeclarations UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace NSAppTransportSecurity UIBackgroundModes; do
    ! /usr/libexec/PlistBuddy -c "Print :${prohibited_key}" "$plist" >/dev/null 2>&1 \
      || fail "Info.plist contains unreviewed key ${prohibited_key}"
  done
done

while IFS= read -r -d $'\0' swift_source; do
  for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
    if /usr/bin/grep -Fqi -- "$prohibited_marker" "$swift_source"; then
      fail "shipping source contains retired recovery marker ${prohibited_marker}: ${swift_source#$repo_root/}"
    fi
  done
done < <(/usr/bin/find "${repo_root}/GITimeline" -maxdepth 1 -type f -name '*.swift' -print0)

print -- "LOCAL_ONLY_SOURCE_VALIDATION: PASS"
print -- "public_lane=manual_fallback runtime_dependency=absent remote_package_pins=0 configurations=AppStore,AppStoreTesting,PhysicalQualification"
