#!/bin/zsh

set -euo pipefail

readonly ipa_path="${1:?usage: ValidateExportedAppStoreIPA.sh /absolute/path/GITimeline.ipa /absolute/path/GITimeline.xcarchive EXPECTED_TEAM_ID EXPECTED_SOURCE_COMMIT EXPECTED_SOURCE_TREE EXPECTED_PRIVACY_URL EXPECTED_SUPPORT_URL}"
readonly archive_path="${2:?exact validated pre-export archive path is required}"
readonly expected_team_id="${3:?expected Apple Developer Team ID is required}"
readonly expected_source_commit="${4:?expected source commit is required}"
readonly expected_source_tree="${5:?expected source tree is required}"
readonly expected_privacy_url="${6:?expected public privacy URL is required}"
readonly expected_support_url="${7:?expected public support URL is required}"

readonly expected_bundle_id="com.omairmkhan.GITimeline"
readonly expected_display_name="GI Journal"
readonly expected_marketing_version="1.0"
readonly expected_build_number="8"
readonly expected_minimum_os_version="17.0"
readonly expected_camera_usage="GI Journal uses the camera to attach a photo to a manual journal entry."
readonly expected_framework_uuid="BD35C88F-B768-3842-B525-B3F54B900F01"
readonly expected_framework_identifier="com.google.odml.litertlm.CLiteRTLM"
readonly expected_framework_linkedit_fileoff="27344896"
readonly expected_framework_normalized_sha256="cda529609840b50a6d9f638b922a57809bc45f7dc57fd79b111505e6cbe6a183"
readonly maximum_uncompressed_bytes=4000000000
readonly maximum_text_segment_bytes=500000000
readonly script_directory="${0:A:h}"
source "${script_directory}/RetiredRecoverySurfaceMarkers.zsh"

fail() {
  print -u2 -- "error: exported App Store IPA validation failed: $1"
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

validate_privacy_api_entry() {
  local manifest="$1"
  local index="$2"
  local expected_category="$3"
  local expected_reason="$4"
  local entry_path="NSPrivacyAccessedAPITypes.${index}"
  local category reason_count reason
  category="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPIType" raw "$manifest" 2>/dev/null)" \
    || fail "privacy manifest is missing API entry ${index} at ${manifest:t}"
  [[ "$category" == "$expected_category" ]] \
    || fail "privacy API entry ${index} at ${manifest:t} is ${category}, expected ${expected_category}"
  reason_count="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons" xml1 -o - "$manifest" \
    | /usr/bin/grep -c '<string>')"
  [[ "$reason_count" == "1" ]] \
    || fail "privacy API entry ${expected_category} at ${manifest:t} must contain exactly one reason"
  reason="$(/usr/bin/plutil -extract "${entry_path}.NSPrivacyAccessedAPITypeReasons.0" raw "$manifest" 2>/dev/null)" \
    || fail "privacy API entry ${expected_category} at ${manifest:t} has no reason"
  [[ "$reason" == "$expected_reason" ]] \
    || fail "privacy API entry ${expected_category} at ${manifest:t} uses ${reason}, expected ${expected_reason}"
}

validate_privacy_manifests() {
  local app_manifest="$1"
  local framework_manifest="$2"
  local manifest
  for manifest in "$app_manifest" "$framework_manifest"; do
    [[ -f "$manifest" ]] || fail "privacy manifest is missing at ${manifest}"
    /usr/bin/plutil -lint "$manifest" >/dev/null || fail "privacy manifest is invalid at ${manifest:t}"
    [[ "$(/usr/bin/plutil -extract NSPrivacyTracking raw "$manifest" 2>/dev/null)" == "false" ]] \
      || fail "privacy tracking must be false at ${manifest:t}"
    [[ "$(/usr/bin/plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
      || fail "collected data types must be empty at ${manifest:t}"
    [[ "$(/usr/bin/plutil -extract NSPrivacyTrackingDomains xml1 -o - "$manifest" 2>/dev/null)" == *"<array/>"* ]] \
      || fail "tracking domains must be empty at ${manifest:t}"
  done
  [[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$app_manifest" | /usr/bin/grep -c '<dict>')" == "4" ]] \
    || fail "app privacy manifest contains an unreviewed accessed-API declaration"
  validate_privacy_api_entry "$app_manifest" 0 NSPrivacyAccessedAPICategoryUserDefaults CA92.1
  validate_privacy_api_entry "$app_manifest" 1 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
  validate_privacy_api_entry "$app_manifest" 2 NSPrivacyAccessedAPICategoryDiskSpace E174.1
  validate_privacy_api_entry "$app_manifest" 3 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1
  [[ "$(/usr/bin/plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$framework_manifest" | /usr/bin/grep -c '<dict>')" == "2" ]] \
    || fail "framework privacy manifest contains an unreviewed accessed-API declaration"
  validate_privacy_api_entry "$framework_manifest" 0 NSPrivacyAccessedAPICategoryFileTimestamp C617.1
  validate_privacy_api_entry "$framework_manifest" 1 NSPrivacyAccessedAPICategorySystemBootTime 35F9.1
}

validate_model_payload_absence() {
  local app_path="$1"
  local unexpected_payload
  unexpected_payload="$(/usr/bin/find "$app_path" \( -type f -o -type l \) -name '*.litertlm' -print -quit)"
  [[ -z "$unexpected_payload" ]] || fail "manual fallback IPA contains a .litertlm model"
  unexpected_payload="$(/usr/bin/find "$app_path" \( -type f -o -type l \) -path '*/EmbeddedModels/*' -print -quit)"
  [[ -z "$unexpected_payload" ]] || fail "manual fallback IPA contains an EmbeddedModels payload"
  [[ ! -e "${app_path}/EmbeddedModels" && ! -L "${app_path}/EmbeddedModels" ]] \
    || fail "manual fallback IPA contains an EmbeddedModels directory"
}

validate_framework_invariant() {
  local app_path="$1"
  local framework_path="$app_path/Frameworks/CLiteRTLM.framework"
  local framework_executable="$framework_path/CLiteRTLM"
  local framework_info="$framework_path/Info.plist"
  [[ -d "$framework_path" && -f "$framework_executable" && -f "$framework_info" ]] \
    || fail "reviewed CLiteRTLM framework is incomplete"
  [[ "$(/usr/bin/stat -f '%Lp' "$framework_executable")" == "755" ]] \
    || fail "CLiteRTLM executable is not mode 0755"
  /usr/bin/codesign --verify --strict "$framework_path" || fail "CLiteRTLM framework signature is invalid"
  local framework_codesign_details
  framework_codesign_details="$(/usr/bin/codesign -dv --verbose=4 "$framework_path" 2>&1)"
  [[ "$framework_codesign_details" == *"Authority=Apple Distribution:"* ]] \
    || fail "CLiteRTLM framework is not signed by an Apple Distribution identity"
  [[ "$framework_codesign_details" == *$'\nTeamIdentifier='"$expected_team_id"$'\n'* ]] \
    || fail "CLiteRTLM framework is not signed by the expected team"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$framework_info" 2>/dev/null)" == "$expected_framework_identifier" ]] \
    || fail "CLiteRTLM framework identifier drifted"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework_info" 2>/dev/null)" == "CLiteRTLM" ]] \
    || fail "CLiteRTLM executable name drifted"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$framework_info" 2>/dev/null)" == "FMWK" ]] \
    || fail "CLiteRTLM package type drifted"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$framework_info" 2>/dev/null)" == "iPhoneOS" ]] \
    || fail "CLiteRTLM does not declare iPhoneOS"
  ! /usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:1' "$framework_info" >/dev/null 2>&1 \
    || fail "CLiteRTLM declares an unreviewed second platform"
  /usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$framework_executable" 2 15.0 \
    || fail "CLiteRTLM Mach-O platform/minimum OS drifted"
  local uuid_output uuid_count framework_uuid framework_arch
  uuid_output="$(/usr/bin/dwarfdump --uuid "$framework_executable")" || fail "could not read CLiteRTLM UUID"
  uuid_count="$(print -r -- "$uuid_output" | /usr/bin/grep -c '^UUID:')"
  [[ "$uuid_count" == "1" ]] || fail "CLiteRTLM must be a single-architecture device framework"
  framework_uuid="$(print -r -- "$uuid_output" | /usr/bin/awk '$1 == "UUID:" && !printed { print $2; printed=1 }')"
  framework_arch="$(print -r -- "$uuid_output" | /usr/bin/awk '$1 == "UUID:" && !printed { gsub(/[()]/, "", $3); print $3; printed=1 }')"
  [[ "$framework_uuid" == "$expected_framework_uuid" && "$framework_arch" == "arm64" ]] \
    || fail "CLiteRTLM UUID/architecture does not match the reviewed arm64 artifact"
  local linkedit_fileoff
  linkedit_fileoff="$(/usr/bin/otool -l "$framework_executable" \
    | /usr/bin/awk '$1 == "segname" && $2 == "__LINKEDIT" { found=1; next } found && !printed && $1 == "fileoff" { print $2; printed=1 }')"
  [[ "$linkedit_fileoff" == "$expected_framework_linkedit_fileoff" ]] \
    || fail "CLiteRTLM __LINKEDIT file offset ${linkedit_fileoff:-unavailable} drifted"
  (( $(/usr/bin/stat -f '%z' "$framework_executable") > expected_framework_linkedit_fileoff )) \
    || fail "CLiteRTLM executable is truncated before __LINKEDIT"
  local normalized_sha256
  normalized_sha256="$(/usr/bin/python3 "$script_directory/NormalizedMachOExecutableHash.py" "$framework_executable" "$linkedit_fileoff")" \
    || fail "could not normalize/hash the CLiteRTLM executable"
  [[ "$normalized_sha256" == "$expected_framework_normalized_sha256" ]] \
    || fail "CLiteRTLM signing-normalized Mach-O SHA-256 drifted"
  print -r -- "$framework_uuid"
}

validate_notices() {
  local notices_path="$1"
  [[ -f "$notices_path" ]] || fail "ThirdPartyNotices.txt is missing"
  local required_notice
  for required_notice in \
    "LiteRT-LM" \
    "2117fc4314670e00047bc8469783f02a68c33f0c" \
    "http://www.apache.org/licenses/LICENSE-2.0" \
    "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"; do
    /usr/bin/grep -Fq "$required_notice" "$notices_path" || fail "ThirdPartyNotices.txt is missing ${required_notice}"
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
      AppIcon60x60@2x.png|AppIcon76x76@2x~ipad.png|Assets.car|GITimeline|Info.plist|PkgInfo|PrivacyInfo.xcprivacy|ThirdPartyNotices.txt|embedded.mobileprovision|_CodeSignature/CodeResources|Frameworks/CLiteRTLM.framework/CLiteRTLM|Frameworks/CLiteRTLM.framework/Info.plist|Frameworks/CLiteRTLM.framework/PrivacyInfo.xcprivacy|Frameworks/CLiteRTLM.framework/_CodeSignature/CodeResources) ;;
      *) fail "bundle contains an unreviewed file: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" -type f -print0)
  while IFS= read -r -d $'\0' bundled_item; do
    relative_path="${bundled_item#$app_path/}"
    [[ "$bundled_item" == "$app_path" ]] && relative_path="."
    case "$relative_path" in
      .|Frameworks|Frameworks/CLiteRTLM.framework|Frameworks/CLiteRTLM.framework/_CodeSignature|_CodeSignature) ;;
      *) fail "bundle contains an unreviewed directory: ${relative_path}" ;;
    esac
  done < <(/usr/bin/find "$app_path" -type d -print0)
}

[[ "$ipa_path" == /* ]] || fail "IPA path must be absolute"
[[ -f "$ipa_path" && "$ipa_path" == *.ipa ]] || fail "IPA does not exist or does not use the .ipa extension"
[[ "$archive_path" == /* ]] || fail "pre-export archive path must be absolute"
[[ -d "$archive_path" && -f "$archive_path/Info.plist" ]] || fail "pre-export archive or its Info.plist is missing"
[[ ${#expected_team_id} == 10 && "$expected_team_id" != *[^A-Z0-9]* ]] || fail "expected team ID must be ten uppercase letters/digits"
[[ ${#expected_source_commit} == 40 && "$expected_source_commit" != *[^0-9a-f]* ]] \
  || fail "expected source commit must be a 40-character lowercase Git commit"
[[ ${#expected_source_tree} == 40 && "$expected_source_tree" != *[^0-9a-f]* ]] \
  || fail "expected source tree must be a 40-character lowercase Git tree"
validate_public_url "$expected_privacy_url"
validate_public_url "$expected_support_url"
readonly ipa_bytes="$(/usr/bin/stat -f '%z' "$ipa_path")"
(( ipa_bytes < maximum_uncompressed_bytes )) || fail "IPA bytes reach or exceed 4,000,000,000"
readonly ipa_sha256="$(/usr/bin/shasum -a 256 "$ipa_path" | /usr/bin/awk '{print $1}')"
readonly archive_application_path="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$archive_path/Info.plist" 2>/dev/null)"
[[ "$archive_application_path" == "Applications/GITimeline.app" ]] \
  || fail "pre-export archive application path is not exactly Applications/GITimeline.app"
readonly archive_app_path="$archive_path/Products/$archive_application_path"
readonly archive_executable_path="$archive_app_path/GITimeline"
[[ -f "$archive_executable_path" ]] || fail "pre-export archive executable is missing"

readonly extraction_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/GIJournal-exported-ipa.XXXXXX")"
readonly entry_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-exported-ipa-entries.XXXXXX")"
readonly entitlements_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-exported-entitlements.XXXXXX")"
readonly profile_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-exported-profile.XXXXXX")"
readonly strings_dump="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/GIJournal-exported-strings.XXXXXX")"
cleanup() {
  /bin/rm -rf "$extraction_root"
  /bin/rm -f "$entry_dump" "$entitlements_dump" "$profile_dump" "$strings_dump"
}
trap cleanup EXIT

/usr/bin/python3 - "$ipa_path" "$entry_dump" "$maximum_uncompressed_bytes" <<'PY' \
  || fail "IPA central-directory safety preflight failed"
import pathlib
import stat
import sys
import unicodedata
import zipfile

ipa_path, entry_dump, maximum_text = sys.argv[1:]
maximum_uncompressed_bytes = int(maximum_text)

def reject(message: str) -> None:
    raise SystemExit(f"error: {message}")

try:
    archive = zipfile.ZipFile(ipa_path, "r")
except (OSError, zipfile.BadZipFile) as error:
    reject(f"IPA central directory could not be read: {error}")

with archive:
    entries = archive.infolist()
    if not entries:
        reject("IPA has no entries")
    if len(entries) > 256:
        reject(f"IPA contains {len(entries)} entries; reviewed maximum is 256")

    raw_names = set()
    normalized_names = set()
    total_uncompressed_bytes = 0
    safe_names = []
    required_executable_entries = {
        "Payload/GITimeline.app/GITimeline": False,
        "Payload/GITimeline.app/Frameworks/CLiteRTLM.framework/CLiteRTLM": False,
    }

    for entry in entries:
        name = entry.filename
        if not name or any(character in name for character in ("\x00", "\r", "\n")):
            reject("IPA contains an empty or control-character entry name")
        if "\\" in name or name.startswith("/"):
            reject("IPA contains an absolute or backslash-delimited entry name")

        parts = pathlib.PurePosixPath(name).parts
        if any(part in ("", ".", "..") for part in parts):
            reject("IPA contains a dot, dot-dot, or empty path component")
        normalized_path = "/".join(parts)
        if name.rstrip("/") != normalized_path or name.endswith("//"):
            reject("IPA contains a path that changes when normalized")
        if not (
            name in ("Payload", "Payload/", "Payload/GITimeline.app", "Payload/GITimeline.app/")
            or name.startswith("Payload/GITimeline.app/")
        ):
            reject("IPA contains an entry outside Payload/GITimeline.app")

        canonical_name = unicodedata.normalize("NFC", normalized_path).casefold()
        if name in raw_names or canonical_name in normalized_names:
            reject("IPA contains a duplicate or filesystem-colliding entry name")
        raw_names.add(name)
        normalized_names.add(canonical_name)

        if entry.flag_bits & 0x1:
            reject("IPA contains an encrypted entry")
        if entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            reject("IPA contains an unsupported compression method")

        unix_mode = (entry.external_attr >> 16) & 0xFFFF
        entry_type = stat.S_IFMT(unix_mode)
        declared_directory = entry.is_dir()
        allowed_types = (0, stat.S_IFREG, stat.S_IFDIR)
        if entry_type not in allowed_types:
            reject("IPA contains a symlink or other non-regular filesystem entry")
        if declared_directory and entry_type == stat.S_IFREG:
            reject("IPA directory is encoded as a regular file")
        if not declared_directory and entry_type == stat.S_IFDIR:
            reject("IPA file is encoded as a directory")
        if declared_directory and entry.file_size != 0:
            reject("IPA directory declares nonzero extracted bytes")
        if normalized_path in required_executable_entries:
            if declared_directory or entry_type not in (0, stat.S_IFREG):
                reject(f"IPA executable entry is not a regular file: {normalized_path}")
            if stat.S_IMODE(unix_mode) != 0o755:
                reject(f"IPA executable entry is not mode 0755: {normalized_path}")
            required_executable_entries[normalized_path] = True

        total_uncompressed_bytes += entry.file_size
        if total_uncompressed_bytes >= maximum_uncompressed_bytes:
            reject("IPA declared uncompressed bytes reach or exceed 4,000,000,000")
        safe_names.append(name)

    missing_executables = [
        name for name, observed in required_executable_entries.items() if not observed
    ]
    if missing_executables:
        reject(f"IPA is missing required executable entry {missing_executables[0]}")

    with open(entry_dump, "w", encoding="utf-8", newline="\n") as output:
        output.write("\n".join(safe_names) + "\n")
PY
[[ -s "$entry_dump" ]] || fail "IPA central-directory preflight produced no reviewed entries"
/usr/bin/unzip -qq "$ipa_path" -d "$extraction_root" || fail "IPA could not be extracted"
[[ "$(/usr/bin/shasum -a 256 "$ipa_path" | /usr/bin/awk '{print $1}')" == "$ipa_sha256" ]] \
  || fail "IPA changed between preflight and extraction"

readonly payload_path="$extraction_root/Payload"
readonly app_path="$payload_path/GITimeline.app"
[[ -d "$payload_path" && -d "$app_path" ]] || fail "Payload/GITimeline.app is missing"
typeset -a payload_apps
payload_apps=("${(@f)$(/usr/bin/find "$payload_path" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print)}")
(( ${#payload_apps[@]} == 1 )) || fail "IPA must contain exactly one top-level app"
[[ "${payload_apps[1]}" == "$app_path" ]] || fail "IPA top-level app is not exactly Payload/GITimeline.app"
readonly outside_payload_file="$(/usr/bin/find "$extraction_root" -type f ! -path "$app_path/*" -print -quit)"
[[ -z "$outside_payload_file" ]] || fail "IPA contains a file outside Payload/GITimeline.app"
readonly extracted_symlink="$(/usr/bin/find "$extraction_root" -type l -print -quit)"
[[ -z "$extracted_symlink" ]] || fail "IPA contains a symlink"

readonly info_path="$app_path/Info.plist"
readonly executable_path="$app_path/GITimeline"
[[ -f "$info_path" && -f "$executable_path" ]] || fail "exported production application is incomplete"
[[ "$(/usr/bin/stat -f '%Lp' "$archive_executable_path")" == "755" ]] \
  || fail "pre-export main executable is not mode 0755"
[[ "$(/usr/bin/stat -f '%Lp' "$executable_path")" == "755" ]] \
  || fail "exported main executable is not mode 0755"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$archive_executable_path" 2 17.0 \
  || fail "pre-export main executable platform/minimum OS drifted"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$executable_path" 2 17.0 \
  || fail "exported main executable platform/minimum OS drifted"
readonly archive_app_uuid="$(single_arm64_uuid "$archive_executable_path" "pre-export archive")"
readonly exported_app_uuid="$(single_arm64_uuid "$executable_path" "exported IPA")"
[[ "$exported_app_uuid" == "$archive_app_uuid" ]] \
  || fail "exported executable UUID does not match the validated pre-export archive"
readonly archive_app_linkedit_fileoff="$(linkedit_fileoff "$archive_executable_path" "pre-export archive")"
readonly exported_app_linkedit_fileoff="$(linkedit_fileoff "$executable_path" "exported IPA")"
[[ "$exported_app_linkedit_fileoff" == "$archive_app_linkedit_fileoff" ]] \
  || fail "exported executable __LINKEDIT offset does not match the pre-export archive"
readonly archive_app_invariant_sha256="$(normalized_macho_sha256 "$archive_executable_path" "$archive_app_linkedit_fileoff" "pre-export archive")"
readonly exported_app_invariant_sha256="$(normalized_macho_sha256 "$executable_path" "$exported_app_linkedit_fileoff" "exported IPA")"
[[ "$exported_app_invariant_sha256" == "$archive_app_invariant_sha256" ]] \
  || fail "exported executable signing-normalized Mach-O does not match the validated pre-export archive"

readonly archive_framework_executable_path="$archive_app_path/Frameworks/CLiteRTLM.framework/CLiteRTLM"
readonly exported_framework_executable_path="$app_path/Frameworks/CLiteRTLM.framework/CLiteRTLM"
[[ -f "$archive_framework_executable_path" && -f "$exported_framework_executable_path" ]] \
  || fail "archive/export CLiteRTLM executable linkage inputs are missing"
[[ "$(/usr/bin/stat -f '%Lp' "$archive_framework_executable_path")" == "755" ]] \
  || fail "pre-export CLiteRTLM executable is not mode 0755"
[[ "$(/usr/bin/stat -f '%Lp' "$exported_framework_executable_path")" == "755" ]] \
  || fail "exported CLiteRTLM executable is not mode 0755"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$archive_framework_executable_path" 2 15.0 \
  || fail "pre-export CLiteRTLM platform/minimum OS drifted"
/usr/bin/python3 "$script_directory/ValidateMachOPlatform.py" "$exported_framework_executable_path" 2 15.0 \
  || fail "exported CLiteRTLM platform/minimum OS drifted"
readonly archive_framework_linkedit_fileoff="$(linkedit_fileoff "$archive_framework_executable_path" "pre-export CLiteRTLM")"
readonly exported_framework_linkedit_fileoff="$(linkedit_fileoff "$exported_framework_executable_path" "exported CLiteRTLM")"
[[ "$archive_framework_linkedit_fileoff" == "$exported_framework_linkedit_fileoff" ]] \
  || fail "exported CLiteRTLM __LINKEDIT offset does not match the pre-export archive"
readonly archive_framework_normalized_sha256="$(normalized_macho_sha256 "$archive_framework_executable_path" "$archive_framework_linkedit_fileoff" "pre-export CLiteRTLM")"
readonly exported_framework_normalized_sha256="$(normalized_macho_sha256 "$exported_framework_executable_path" "$exported_framework_linkedit_fileoff" "exported CLiteRTLM")"
[[ "$archive_framework_normalized_sha256" == "$exported_framework_normalized_sha256" ]] \
  || fail "exported CLiteRTLM signing-normalized Mach-O does not match the pre-export archive"

/usr/bin/python3 "$script_directory/CompareNormalizedAppPayloadFiles.py" "$archive_app_path" "$app_path" \
  || fail "exported non-signing payload does not exactly match the pre-export archive"
/usr/bin/codesign --verify --deep --strict "$app_path" || fail "app or embedded framework signature is invalid"
readonly codesign_details="$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)"
[[ "$codesign_details" == *"Authority=Apple Distribution:"* ]] || fail "app is not signed by an Apple Distribution identity"
[[ "$codesign_details" == *$'\nIdentifier='"$expected_bundle_id"$'\n'* || "$codesign_details" == Identifier="$expected_bundle_id"$'\n'* ]] \
  || fail "signed code identifier does not match the production bundle ID"
[[ "$codesign_details" == *$'\nTeamIdentifier='"$expected_team_id"$'\n'* ]] || fail "signed code team identifier does not match"

/usr/bin/codesign -d --entitlements :- "$app_path" > "$entitlements_dump" 2>/dev/null || fail "signed entitlements could not be read"
/usr/bin/plutil -lint "$entitlements_dump" >/dev/null || fail "signed entitlements are not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$entitlements_dump" 2>/dev/null)" == "${expected_team_id}.${expected_bundle_id}" ]] \
  || fail "application-identifier entitlement does not match the production App ID"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$entitlements_dump" 2>/dev/null)" == "$expected_team_id" ]] \
  || fail "team entitlement does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements_dump" 2>/dev/null || true)" != "true" ]] || fail "exported app permits debugging"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :beta-reports-active' "$entitlements_dump" 2>/dev/null)" == "true" ]] \
  || fail "exported app is missing beta-reports-active"
readonly signed_entitlement_keys="$(/usr/libexec/PlistBuddy -c 'Print' "$entitlements_dump" \
  | /usr/bin/sed -n 's/^[[:space:]]*\([^ =]*\)[[:space:]]*=.*$/\1/p' | LC_ALL=C /usr/bin/sort)"
while IFS= read -r entitlement_key; do
  case "$entitlement_key" in
    application-identifier|beta-reports-active|com.apple.developer.team-identifier|get-task-allow) ;;
    *) fail "unexpected exported entitlement ${entitlement_key}" ;;
  esac
done <<< "$signed_entitlement_keys"

readonly embedded_profile="$app_path/embedded.mobileprovision"
[[ -f "$embedded_profile" ]] || fail "embedded App Store provisioning profile is missing"
/usr/bin/security cms -D -i "$embedded_profile" > "$profile_dump" 2>/dev/null || fail "embedded profile could not be decoded"
/usr/bin/plutil -lint "$profile_dump" >/dev/null || fail "embedded provisioning profile is invalid"
typeset profile_expiration
profile_expiration="$(validated_profile_expiration "$profile_dump")" \
  || fail "embedded App Store provisioning profile is expired or has no valid expiration"
readonly profile_expiration
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_dump" 2>/dev/null)" == "$expected_team_id" ]] || fail "profile team does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_dump" 2>/dev/null)" == "${expected_team_id}.${expected_bundle_id}" ]] || fail "profile does not authorize the production App ID"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile_dump" 2>/dev/null || true)" != "true" ]] || fail "profile permits debugging"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:beta-reports-active' "$profile_dump" 2>/dev/null)" == "true" ]] || fail "profile is not App Store Connect/TestFlight enabled"
! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile_dump" >/dev/null 2>&1 || fail "profile contains provisioned devices"
! /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$profile_dump" >/dev/null 2>&1 || fail "profile is an enterprise profile"

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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :UISupportedInterfaceOrientations:0' "$info_path" 2>/dev/null)" == "UIInterfaceOrientationPortrait" ]] || fail "app orientation contract is not portrait"
! /usr/libexec/PlistBuddy -c 'Print :UISupportedInterfaceOrientations:1' "$info_path" >/dev/null 2>&1 || fail "app declares an unreviewed second orientation"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_path")" == "false" ]] || fail "non-exempt encryption declaration is not false"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GIPrivacyPolicyURL' "$info_path" 2>/dev/null)" == "$expected_privacy_url" ]] || fail "privacy-policy URL does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISupportURL' "$info_path" 2>/dev/null)" == "$expected_support_url" ]] || fail "support URL does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceCommit' "$info_path" 2>/dev/null)" == "$expected_source_commit" ]] || fail "source commit does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :GISourceTree' "$info_path" 2>/dev/null)" == "$expected_source_tree" ]] || fail "source tree does not match"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$info_path" 2>/dev/null)" == "$expected_camera_usage" ]] || fail "camera usage description drifted"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$info_path" 2>/dev/null)" == "AppIcon" ]] || fail "primary app icon metadata is missing"
for prohibited_key in CFBundleDocumentTypes CFBundleURLTypes UTExportedTypeDeclarations UTImportedTypeDeclarations UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
  ! /usr/libexec/PlistBuddy -c "Print :${prohibited_key}" "$info_path" >/dev/null 2>&1 || fail "public app exposes a document, URL, or file-type surface through ${prohibited_key}"
done

validate_model_payload_absence "$app_path"
validate_privacy_manifests "$app_path/PrivacyInfo.xcprivacy" "$app_path/Frameworks/CLiteRTLM.framework/PrivacyInfo.xcprivacy"
validate_notices "$app_path/ThirdPartyNotices.txt"
[[ -f "$app_path/Assets.car" ]] || fail "compiled assets are missing"
validate_closed_payload "$app_path"
readonly framework_uuid="$(validate_framework_invariant "$app_path")"

/usr/bin/strings -a "$executable_path" > "$strings_dump" || fail "could not inspect production executable strings"
for prohibited_marker in --show-developer-tools --ui-test-ephemeral-store --run-overnight-gemma-smoke --run-embedded-gemma-smoke --internal-app-store-raw-image-v1 --diagnose-app-store-raw-image-v1-gpu-main-cpu-vision70-ab diagnostic-app-store-raw-image-v1-gpu-main-cpu-vision70 --diagnose-app-store-raw-image-v1-preparation --diagnose-app-store-raw-image-v1-preparation-fresh-cache --diagnose-app-store-raw-image-v1-preparation-caches-root --diagnose-app-store-raw-image-v1-direct-image-data --diagnose-app-store-raw-image-v1-sync-send-ab conversation_send_message_sync_v1 sync_send_start sync_cancel_requested sync_quarantined fresh_isolated_diagnostic_cache fresh_caches_root_diagnostic_cache InternalRawImageV1PreparationCache InternalRawImageV1PreparationCaches --run-embedded-gemma-normal-flow --verify-embedded-gemma-normal-flow --run-physical-raw-image --run-photo-evaluation-derived-map-iphone --run-photo-evaluation-raw-image-simulator --run-photo-tuning-derived-map-v3 --run-photo-blind-validation-v3 --run-raw-photo-v12-tuning-simulator-baseline --run-raw-photo-v12-tuning-simulator-candidate --raw-photo-v12-tuning-fixture- GI_JOURNAL_UI_EVIDENCE_SEEDED EMBEDDED_GEMMA_NORMAL_FLOW_PASS EMBEDDED_GEMMA_RELAUNCH_PASS EMBEDDED_GEMMA_COMPLETION_FAIL APP_STORE_RAW_IMAGE_V1_PREPARATION PHOTO_TUNING_V3_RUN_COMPLETE PHOTO_BLIND_VALIDATION_V1_RUN_COMPLETE RAW_PHOTO_V12_TUNING RawPhotoV12TuningV1 raw-photo-v12-subject-gate-tuning-v1 RawPhotoV12TuningAttemptLedgerV1 holdout_manifest_access isolation_attested 00d8e8bc11b8ba83d4cb624bc69e45542b7aae0420a45b17d66e52232d34e7bc diagnostic-app-store-raw-image-v1.2-subject-gate-tuning-v1 gi-photo-v1.2-subject-gate-tuning-v1 GIJournalBlindValidationV1; do
  ! /usr/bin/grep -Fq -- "$prohibited_marker" "$strings_dump" || fail "production executable contains prohibited marker ${prohibited_marker}"
done
for prohibited_marker in "${RETIRED_RECOVERY_SURFACE_MARKERS[@]}"; do
  ! /usr/bin/grep -Fqi -- "$prohibited_marker" "$strings_dump" || fail "production executable contains retired recovery marker ${prohibited_marker}"
done

typeset -i app_text_bytes framework_text_bytes total_text_bytes app_regular_file_bytes=0 extracted_regular_file_bytes=0
app_text_bytes="$(/usr/bin/size -m "$executable_path" | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
framework_text_bytes="$(/usr/bin/size -m "$app_path/Frameworks/CLiteRTLM.framework/CLiteRTLM" | /usr/bin/awk '$1 == "Segment" && $2 == "__TEXT:" && !printed { print $3; printed=1 }')"
(( app_text_bytes > 0 && framework_text_bytes > 0 )) || fail "could not measure executable __TEXT segments"
total_text_bytes=$(( app_text_bytes + framework_text_bytes ))
(( total_text_bytes < maximum_text_segment_bytes )) || fail "executable __TEXT bytes reach or exceed the release ceiling"
while IFS= read -r -d $'\0' bundled_file; do (( app_regular_file_bytes += $(/usr/bin/stat -f '%z' "$bundled_file") )); done < <(/usr/bin/find "$app_path" -type f -print0)
(( app_regular_file_bytes < maximum_uncompressed_bytes )) || fail "app regular-file bytes reach or exceed 4,000,000,000"
while IFS= read -r -d $'\0' extracted_file; do (( extracted_regular_file_bytes += $(/usr/bin/stat -f '%z' "$extracted_file") )); done < <(/usr/bin/find "$extraction_root" -type f -print0)
(( extracted_regular_file_bytes < maximum_uncompressed_bytes )) || fail "extracted IPA regular-file bytes reach or exceed 4,000,000,000"

print -- "EXPORTED_APPSTORE_IPA_VALIDATION: PASS"
print -- "team=${expected_team_id} identity=Apple_Distribution profile_expiration=${profile_expiration} bundle_id=${expected_bundle_id} version=${expected_marketing_version} build=${expected_build_number} source_commit=${expected_source_commit} source_tree=${expected_source_tree} app_uuid=${exported_app_uuid} app_normalized_sha256=${exported_app_invariant_sha256} framework_uuid=${framework_uuid} framework_normalized_sha256=${expected_framework_normalized_sha256} app_regular_file_bytes=${app_regular_file_bytes} ipa_bytes=${ipa_bytes} ipa_sha256=${ipa_sha256} model_payload=absent"
