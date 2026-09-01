#!/bin/zsh

# Internal Qwen3 physical qualification only. This script builds and installs
# the isolated QA bundle; it never modifies, installs, or inspects production.

set -euo pipefail
umask 077

readonly script_path="${0:A}"
readonly repo_root="${script_path:h:h}"
readonly qa_project="$repo_root/GITimelineQwen3QA.xcodeproj"
readonly qa_scheme="GITimeline Qwen3 QA"
readonly qa_bundle_id="com.omairmkhan.GITimeline.qwen3qa"
readonly qa_executable_name="GITimeline"
readonly source_snapshot="${QWEN3_SNAPSHOT_PATH:-}"
readonly journal_relative_path="Library/Application Support/Qwen3DecomposedPhysicalQA/physical-runs.jsonl"
readonly source_packages="${SOURCE_PACKAGES_DIR:-}"

typeset -A expected_snapshot_sha256
expected_snapshot_sha256=(
  .gitattributes 34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930
  README.md ede73d0babc5bc8fa1eeaed1f9564eab6e5094500e5561f94235a15c96aa1cf0
  added_tokens.json c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680
  chat_template.jinja 3636d0f0bd6bef02654cdffdc447b79cb2cef8ab02cc75267345946291a489e4
  chat_template.json 6f8a6a55027e3da5160105556cda5dd69f6423f1c32645f6730d32de7773d0c4
  config.json 6e992843f82cbaf02e8eae2f1c803f8a56f70951fa8a1f30fc1bf8d9ec2d7ec3
  generation_config.json 1e241830b48b397cb0900101421df5450baddc7adf01e5fc86b5615865f3bae4
  merges.txt 8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5
  model.safetensors 4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb
  model.safetensors.index.json 30ba24b1c93436450f2e202de402058ecea7417cf66785d4c73e52d1575e6d97
  preprocessor_config.json 93585062a80db5e8ca038efc7726a3e6411d9db948472d81d63c6303993be8c5
  special_tokens_map.json 76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd
  tokenizer.json aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4
  tokenizer_config.json 81ec7bb9530159b326c0bef1d0b6c33d392090524014ea3f0123a3c1eb9c2af5
  video_preprocessor_config.json 59c5c9eb52182eb14c06ffb10ca9effd29adce5f238a95de23ca14a38dbd2cb1
  vocab.json ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910
)

# Pinned (fixed attach order: formed-brown, loose-yellow, red-visible,
# black-glossy, blank-unusable) sha256 of the five frozen synthetic fixtures
# the unattended INTERNAL_QWEN3_QA autorun coordinator embeds and attaches.
# Kept in lockstep with lane/Tools/pin_autorun_controls.py's PINNED_TABLE and
# the qwen3QAFixtures constant in Qwen3HybridPhotoSuggestionEngine.swift.
readonly qa_autorun_fixture_shas="4deae91617420220ee5434bfa3305099a3db9c2405ca3846539938b3de8ecda7,59ede3a965547888addb6b8b446c17a9c4378ea986275f888e5f5f9f02064a77,8f31b49966fdd4c31b2ea2ce1b7062daee81960d4d312b260af48210a5d38c7e,243a63da852fa182a1720ba8af417d3e973da44c2a0bd6d7b255272af83720fd,5c86ed41bb0cb85ea6cc28b00dd104e7a72b52bbfdcb729dd79a19c87b8438a2"

usage() {
  print -r -- "usage: TEAM_ID=<AppleTeamID> UDID=<trusted_iPhone_UDID> $script_path [--help]"
  print -r -- ""
  print -r -- "Optional: INPUT_SIZE=512 (default), INPUT_SIZE=1024 for the explicit QA profile,"
  print -r -- "  or INPUT_SIZE=256 with ALLOW_256_RESOURCE_FALLBACK=YES."
  print -r -- "Required: QWEN3_SNAPSHOT_PATH=<local pinned Qwen3 snapshot>."
  print -r -- "Required: SOURCE_PACKAGES_DIR=<pre-existing pinned SourcePackages>."
  print -r -- "Required: EVIDENCE_ROOT=<new local evidence directory>."
  print -r -- "Optional: LAUNCH_TIMEOUT_SECONDS=3600."
  print -r -- "Optional: UNATTENDED=YES (default NO) drives the five pinned synthetic fixtures automatically"
  print -r -- "  in fixed order and exits on completion or first failure; nothing is attached manually."
  print -r -- "Use owner-approved synthetic QA images only; never attach private journal or private photos."
  print -r -- "The launch is interactive and records raw model field output only in the isolated QA app container."
}

fail() {
  print -u2 -r -- "QWEN3_PHYSICAL_QUALIFICATION: FAIL: $*"
  exit 1
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
[[ $# -eq 0 ]] || { usage; fail "unexpected argument"; }

[[ -n "${TEAM_ID:-}" ]] || fail "TEAM_ID is required"
[[ -n "${UDID:-}" ]] || fail "UDID is required"
[[ -n "$source_snapshot" ]] || fail "QWEN3_SNAPSHOT_PATH is required"
[[ -n "$source_packages" ]] || fail "SOURCE_PACKAGES_DIR is required"
readonly team_id="$TEAM_ID"
readonly udid="$UDID"
readonly input_size="${INPUT_SIZE:-512}"
case "$input_size" in
  1024) ;;
  512) ;;
  256) [[ "${ALLOW_256_RESOURCE_FALLBACK:-NO}" == "YES" ]] || fail "256 requires ALLOW_256_RESOURCE_FALLBACK=YES" ;;
  *) fail "INPUT_SIZE must be exactly 1024, 512, or 256" ;;
esac
readonly unattended="${UNATTENDED:-NO}"
case "$unattended" in
  YES) ;;
  NO) ;;
  *) fail "UNATTENDED must be exactly YES or NO" ;;
esac
readonly launch_timeout_seconds="${LAUNCH_TIMEOUT_SECONDS:-3600}"
[[ "$launch_timeout_seconds" == <-> && "$launch_timeout_seconds" -gt 0 ]] \
  || fail "LAUNCH_TIMEOUT_SECONDS must be a positive integer"
print -r -- "DEVICE STORAGE PREREQUISITE: reserve at least 4 GB on the trusted iPhone; this is not proof of current free space."

[[ -n "${EVIDENCE_ROOT:-}" ]] || fail "EVIDENCE_ROOT is required"
readonly evidence_root="$EVIDENCE_ROOT"
case "$evidence_root" in
  /*) ;;
  *) fail "EVIDENCE_ROOT must be an absolute path to a new local evidence directory" ;;
esac
[[ ! -e "$evidence_root" ]] || fail "EVIDENCE_ROOT already exists; refusing to overwrite evidence"
mkdir -m 700 "$evidence_root"

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

validate_snapshot() {
  local root="$1"
  local comparison_root="${2:-}"
  [[ -d "$root" && ! -L "$root" ]] || fail "snapshot root is missing or symlinked: $root"
  [[ -z "$(/usr/bin/find "$root" -mindepth 1 -type l -print -quit)" ]] || fail "snapshot contains a symlink"
  [[ -z "$(/usr/bin/find "$root" -mindepth 1 -type d -print -quit)" ]] || fail "snapshot contains an unexpected directory"

  local path relative expected actual
  integer actual_count=0
  while IFS= read -r -d '' path; do
    relative="${path#$root/}"
    expected="${expected_snapshot_sha256[$relative]-}"
    [[ -n "$expected" ]] || fail "snapshot has an unexpected file: $relative"
    actual="$(sha256 "$path")"
    [[ "$actual" == "$expected" ]] || fail "snapshot SHA-256 mismatch: $relative"
    if [[ -n "$comparison_root" ]] && ! /usr/bin/cmp -s "$comparison_root/$relative" "$path"; then
      fail "built snapshot bytes differ from pinned source: $relative"
    fi
    (( actual_count += 1 ))
  done < <(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type f -print0)
  (( actual_count == 16 )) || fail "snapshot must contain exactly 16 regular files"
}

validate_source_packages() {
  [[ -d "$source_packages" && ! -L "$source_packages" ]] \
    || fail "SOURCE_PACKAGES_DIR must be a pre-existing non-symlinked directory: $source_packages"
  [[ -f "$source_packages/workspace-state.json" ]] \
    || fail "SOURCE_PACKAGES_DIR is not an existing resolved SwiftPM workspace"
  local checkout
  for checkout in mlx-swift mlx-swift-lm swift-transformers swift-huggingface; do
    [[ -d "$source_packages/checkouts/$checkout" && ! -L "$source_packages/checkouts/$checkout" ]] \
      || fail "SOURCE_PACKAGES_DIR is missing pinned checkout: $checkout"
  done
}

validate_signed_qa_app() {
  local app_path="$1"
  [[ -d "$app_path" && ! -L "$app_path" ]] || fail "missing QA app bundle"
  /usr/bin/plutil -lint "$app_path/Info.plist" >/dev/null
  local bundle_id
  bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app_path/Info.plist")"
  [[ "$bundle_id" == "$qa_bundle_id" ]] || fail "unexpected bundle identifier: $bundle_id"
  validate_snapshot "$app_path/Qwen3Snapshot" "$source_snapshot"

  local cmlx_paths
  cmlx_paths=("${(@f)$(/usr/bin/find "$app_path" -type d -name 'mlx-swift_Cmlx.bundle' -print)}")
  (( ${#cmlx_paths} == 1 )) || fail "expected exactly one MLX Cmlx bundle"
  [[ "${cmlx_paths[1]}" == "$app_path/mlx-swift_Cmlx.bundle" ]] || fail "Cmlx bundle is not app-root iPhoneOS input"
  [[ ! -d "${cmlx_paths[1]}/Contents/MacOS" ]] || fail "Cmlx bundle contains a macOS payload"
  [[ -n "$(/usr/bin/find "${cmlx_paths[1]}" -type f -name '*.metallib' -print -quit)" ]] || fail "Cmlx metallib missing"
  [[ -z "$(/usr/bin/find "$app_path" -type f \( -iname '*gemma*' -o -name '*.litertlm' \) -print -quit)" ]] || fail "Gemma payload leaked into isolated QA app"

  [[ -x "$app_path/$qa_executable_name" ]] || fail "QA executable missing"
  [[ "$(/usr/bin/lipo -archs "$app_path/$qa_executable_name")" == "arm64" ]] || fail "QA executable must be arm64 only"
  /usr/bin/codesign -dvv "$app_path" 2>"$evidence_root/codesign.txt"
  /usr/bin/grep -Fx "Identifier=$qa_bundle_id" "$evidence_root/codesign.txt" >/dev/null || fail "signature identifier mismatch"
  /usr/bin/grep -Fx "TeamIdentifier=$team_id" "$evidence_root/codesign.txt" >/dev/null || fail "signature team mismatch"

  local profile="$app_path/embedded.mobileprovision"
  [[ -f "$profile" ]] || fail "signed QA app lacks embedded profile"
  /usr/bin/security cms -D -i "$profile" >"$evidence_root/profile.plist"
  /usr/bin/plutil -lint "$evidence_root/profile.plist" >/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$evidence_root/profile.plist")" == "$team_id" ]] || fail "profile team mismatch"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$evidence_root/profile.plist")" == "$team_id.$qa_bundle_id" ]] || fail "profile application identifier mismatch"
  /usr/bin/python3 - "$evidence_root/profile.plist" "$udid" <<'PY'
import plistlib
import sys

profile_path, requested_udid = sys.argv[1:]
with open(profile_path, "rb") as handle:
    profile = plistlib.load(handle)
if requested_udid not in profile.get("ProvisionedDevices", []):
    raise SystemExit("requested UDID is not present in ProvisionedDevices")
PY
  /usr/bin/codesign -d --entitlements :- "$app_path" >"$evidence_root/entitlements.plist" 2>"$evidence_root/entitlements.codesign.txt"
  /usr/bin/plutil -lint "$evidence_root/entitlements.plist" >/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$evidence_root/entitlements.plist")" == "$team_id.$qa_bundle_id" ]] || fail "signed entitlement identifier mismatch"

  /usr/bin/grep -Fq 'mlx-community/Qwen3-VL-2B-Instruct-4bit' "$repo_root/GITimeline/Qwen3HybridPhotoSuggestionEngine.swift" || fail "pinned Qwen identifier missing from internal engine"
  /usr/bin/grep -Fq 'MLX Swift LM 3.31.4' "$repo_root/GITimeline/Qwen3HybridPhotoSuggestionEngine.swift" || fail "pinned MLX identifier missing from internal engine"
  local executable_strings="$evidence_root/executable-strings.txt"
  /usr/bin/strings "$app_path/$qa_executable_name" >"$executable_strings"
  /usr/bin/grep -Fx 'mlx-community/Qwen3-VL-2B-Instruct-4bit' "$executable_strings" >/dev/null \
    || fail "pinned Qwen identifier missing from QA executable"
  /usr/bin/grep -Fq '0.31.6; MLX Swift LM 3.31.4' "$executable_strings" \
    || fail "pinned MLX identity missing from QA executable"
}

validate_snapshot "$source_snapshot"
validate_source_packages
[[ -d "$qa_project" && ! -L "$qa_project" ]] || fail "isolated QA project is unavailable"
/usr/bin/grep -Fq 'com.omairmkhan.GITimeline.qwen3qa' "$qa_project/project.pbxproj" || fail "QA project bundle identifier drifted"

readonly derived_data="$evidence_root/DerivedData"
print -r -- "Building signed isolated QA app (profile=$input_size) into $evidence_root using $source_packages"
/usr/bin/xcodebuild \
  -project "$qa_project" \
  -scheme "$qa_scheme" \
  -configuration Release \
  -destination "platform=iOS,id=$udid" \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$source_packages" \
  -disableAutomaticPackageResolution \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Automatic \
  build | /usr/bin/tee "$evidence_root/build.log"

readonly qa_app="$derived_data/Build/Products/Release-iphoneos/GITimeline.app"
validate_signed_qa_app "$qa_app"

/usr/bin/xcrun devicectl list devices --json-output "$evidence_root/devices.json" >/dev/null
print -r -- "Installing only $qa_bundle_id; no production app is removed or inspected."
/usr/bin/xcrun devicectl device install app \
  --device "$udid" \
  --json-output "$evidence_root/install.json" \
  --log-output "$evidence_root/install.log" \
  "$qa_app"

typeset -a launch_extra_args
launch_extra_args=()
if [[ "$unattended" == "YES" ]]; then
  launch_extra_args+=(--qwen3-qa-autorun)
  print -r -- "Launching the internal QA app in UNATTENDED mode: it drives all five pinned synthetic fixtures itself, in fixed order, and exits on completion or first failure. Do not attach anything manually; never attach private journal or private photos."
else
  print -r -- "Launching the internal QA app. Attach only an owner-approved synthetic QA image; never attach private journal or private photos. Allow the run to finish, then terminate the QA app to collect its JSONL."
fi
set +e
/usr/bin/xcrun devicectl device process launch \
  --device "$udid" \
  --terminate-existing \
  --console \
  --timeout "$launch_timeout_seconds" \
  --json-output "$evidence_root/launch.json" \
  --log-output "$evidence_root/launch.log" \
  "$qa_bundle_id" \
  --qwen3-decomposed-internal-qa \
  "--qwen3-decomposed-preprocess=$input_size" \
  --qwen3-physical-evidence-jsonl \
  "${launch_extra_args[@]}"
launch_status=$?
set -e

/usr/bin/xcrun devicectl device copy from \
  --device "$udid" \
  --domain-type appDataContainer \
  --domain-identifier "$qa_bundle_id" \
  --source "$journal_relative_path" \
  --destination "$evidence_root/physical-runs.jsonl" \
  --json-output "$evidence_root/copy-jsonl.json" \
  --log-output "$evidence_root/copy-jsonl.log"

/usr/bin/python3 "$repo_root/Scripts/ValidateQwen3ResolutionEvidence.py" \
  "$evidence_root/physical-runs.jsonl" "$input_size"

set +e
/usr/bin/python3 - "$evidence_root/physical-runs.jsonl" "$input_size" "$unattended" "$qa_autorun_fixture_shas" <<'PY'
import json
import re
import sys

path, requested_profile, unattended, qa_autorun_fixture_shas = sys.argv[1:]
qa_autorun_pinned_shas = qa_autorun_fixture_shas.split(",")
expected_fields = {"subject", "bristol", "mixed", "color", "red", "black", "glossy"}
sha256 = re.compile(r"[0-9a-f]{64}")


def fail(message):
    raise SystemExit(f"QWEN3_PHYSICAL_JSONL: FAIL: {message}")


def exact_sha256(value):
    return isinstance(value, str) and sha256.fullmatch(value) is not None


def request_events(segment, request_id, event_name):
    return [record for record in segment if record.get("requestID") == request_id and record.get("event") == event_name]


def validate_notifications(segment):
    for record in segment:
        if record.get("event") not in {"memory_warning_notification", "thermal_state_notification"}:
            continue
        profile = record.get("profile")
        if profile not in (None, requested_profile):
            fail("notification profile does not match the requested profile")
        request_id = record.get("requestID")
        if request_id is not None and (not isinstance(request_id, str) or not request_id):
            fail("notification requestID is malformed")
        image_sha = record.get("analyzedImageSHA256")
        if image_sha is not None and not exact_sha256(image_sha):
            fail("notification image hash is malformed")


def validate_started_requests(segment, require_unqualified):
    starts = [record for record in segment if record.get("event") == "request_started"]
    if not starts:
        fail("request_started evidence is missing")
    request_ids = set()
    request_images = {}
    request_tensors = {}
    for start in starts:
        request_id = start.get("requestID")
        image_sha = start.get("analyzedImageSHA256")
        if not isinstance(request_id, str) or not request_id or request_id in request_ids:
            fail("request_started IDs must be unique and nonempty")
        if not exact_sha256(image_sha):
            fail("request_started image hash is malformed")
        request_ids.add(request_id)
        request_images[request_id] = image_sha

        preprocess = request_events(segment, request_id, "preprocess_completed")
        if len(preprocess) != 1:
            fail(f"request {request_id} must have exactly one preprocess_completed event")
        preprocess = preprocess[0]
        tensor_sha = preprocess.get("preparedTensorSHA256")
        if preprocess.get("analyzedImageSHA256") != image_sha or not exact_sha256(tensor_sha):
            fail(f"request {request_id} preprocess image/tensor binding is invalid")
        request_tensors[request_id] = tensor_sha

        fields = request_events(segment, request_id, "field_completed")
        if len(fields) != 7:
            fail(f"request {request_id} must have exactly seven field_completed events")
        observed_fields = set()
        observed_ordinals = set()
        for field_event in fields:
            record = field_event.get("fieldRecord")
            if not isinstance(record, dict):
                fail(f"request {request_id} field record is missing")
            field = record.get("field")
            ordinal = record.get("modelCallOrdinal")
            if field not in expected_fields or field in observed_fields:
                fail(f"request {request_id} fields are not distinct and complete")
            if not isinstance(ordinal, int) or ordinal in observed_ordinals:
                fail(f"request {request_id} field call ordinals are not distinct")
            raw_text = record.get("rawText")
            raw_tokens = record.get("rawTokenIDs")
            if not isinstance(raw_text, str) or not raw_text:
                fail(f"request {request_id} field {field} rawText is empty")
            if not isinstance(raw_tokens, list) or not raw_tokens or not all(isinstance(token, int) for token in raw_tokens):
                fail(f"request {request_id} field {field} rawTokenIDs are empty or malformed")
            if record.get("analyzedImageSHA256") != image_sha or record.get("preparedTensorSHA256") != tensor_sha:
                fail(f"request {request_id} field {field} image/tensor binding does not match preprocess")
            if field_event.get("analyzedImageSHA256") != image_sha or field_event.get("preparedTensorSHA256") != tensor_sha:
                fail(f"request {request_id} field {field} outer image/tensor binding does not match preprocess")
            if require_unqualified and record.get("qualified") is not False:
                fail(f"256 fallback field {field} must remain unqualified")
            observed_fields.add(field)
            observed_ordinals.add(ordinal)
        if observed_fields != expected_fields or observed_ordinals != set(range(1, 8)):
            fail(f"request {request_id} does not have the canonical seven field/call ordinals")
    return request_ids, request_images, request_tensors


records = []
with open(path, "r", encoding="utf-8") as handle:
    for line_number, line in enumerate(handle, 1):
        if not line.endswith("\n"):
            fail(f"line {line_number} is not newline-terminated")
        record = json.loads(line)
        if record.get("schemaVersion") != "qwen3-decomposed-physical-evidence-v2":
            fail(f"unexpected schema on line {line_number}")
        if not record.get("event") or not record.get("timestamp"):
            fail(f"missing event or timestamp on line {line_number}")
        records.append(record)

ready_indexes = [
    index for index, record in enumerate(records)
    if record.get("event") == "journal_ready" and record.get("profile") == requested_profile
]
if not ready_indexes:
    fail(f"journal_ready for requested profile {requested_profile} is missing")
segment = records[ready_indexes[-1]:]
events = [record.get("event") for record in segment]
validate_notifications(segment)

if "model_load_failed" in events:
    fail("model_load_failed is present after the requested journal_ready")
if "model_load_succeeded" not in events:
    fail("model_load_succeeded is missing after the requested journal_ready")

if unattended == "YES":
    # Whole-file scan (not just the post-journal_ready segment): better
    # diagnostics if fixture 1 fails before/around model load, since a
    # coordinator-side failure can be journaled slightly out of step with
    # journal_ready ordering.
    whole_file_failed_autoruns = [record for record in records if record.get("event") == "qa_autorun_failed"]
    if whole_file_failed_autoruns:
        fail(f"qa_autorun_failed present anywhere in the JSONL: {[record.get('detail') for record in whole_file_failed_autoruns]}")
    completed_autoruns = [record for record in segment if record.get("event") == "qa_autorun_completed"]
    if len(completed_autoruns) != 1:
        fail(f"expected exactly one qa_autorun_completed event, found {len(completed_autoruns)}")
    autorun_detail = completed_autoruns[0].get("detail") or ""
    detail_fields = dict(part.split("=", 1) for part in autorun_detail.split(";") if "=" in part)
    if detail_fields.get("fixtures") != "5":
        fail(f"qa_autorun_completed detail does not parse to fixtures=5: {autorun_detail!r}")
    # "analyzed" is the coordinator's own per-fixture sanitized-JPEG hash
    # (from EntryFlowState.reading's imageHash, bound synchronously by
    # installPrepared) — provably tied to what the engine actually
    # processed, unlike the source-PNG sha this validator used to compare
    # against its own argv-echoed pins (a tautology: neither side of that
    # comparison depended on runtime evidence). Source-PNG pins remain
    # enforced Swift-side in verifiedFixtureData and Python-side in the
    # source tests; this validator now binds only to journaled evidence.
    analyzed_field = detail_fields.get("analyzed", "")
    analyzed_shas = analyzed_field.split(",") if analyzed_field else []
    if len(analyzed_shas) != 5 or len(set(analyzed_shas)) != 5:
        fail(f"qa_autorun_completed analyzed list must contain exactly five distinct values: {analyzed_field!r}")
    started_request_ids, request_images, _ = validate_started_requests(segment, require_unqualified=False)
    if len(started_request_ids) != 5:
        fail(f"expected exactly five started requests in unattended mode, found {len(started_request_ids)}")
    if set(analyzed_shas) != set(request_images.values()):
        fail("qa_autorun_completed analyzed list does not match request_started's analyzedImageSHA256 values")

if requested_profile in {"1024", "512"}:
    forbidden = {"request_failed", "resource_fallback_not_semantically_admitted"}
    if forbidden & set(events):
        fail(f"{requested_profile} qualification segment contains forbidden events: {sorted(forbidden & set(events))}")
    request_ids, request_images, _ = validate_started_requests(segment, require_unqualified=False)
    completed_ids = set()
    for request_id in request_ids:
        completed = request_events(segment, request_id, "request_completed")
        if len(completed) != 1:
            fail(f"{requested_profile} request {request_id} must have exactly one request_completed event")
        if completed[0].get("analyzedImageSHA256") != request_images[request_id]:
            fail(f"{requested_profile} request {request_id} completion image hash does not match request")
        if completed[0].get("modelCallCount") != 7:
            fail(f"{requested_profile} request {request_id} completion does not report seven calls")
        request_latency = completed[0].get("requestLatencyMilliseconds")
        if isinstance(request_latency, bool) or not isinstance(request_latency, int) or request_latency < 0:
            fail(f"{requested_profile} request {request_id} completion lacks an exact nonnegative total latency")
        completed_ids.add(request_id)
    all_completed_ids = {record.get("requestID") for record in segment if record.get("event") == "request_completed"}
    if completed_ids != request_ids or all_completed_ids != request_ids:
        fail(f"every started {requested_profile} request must complete exactly once")
    print(f"QWEN3_PHYSICAL_JSONL: STRUCTURAL_PASS profile={requested_profile} requests={len(request_ids)} events={len(segment)}; structural evidence only, not semantic, mini-set, offline, or full physical qualification")
elif requested_profile == "256":
    request_ids, _, _ = validate_started_requests(segment, require_unqualified=True)
    if "request_completed" in events:
        fail("256 resource fallback must not emit request_completed")
    for request_id in request_ids:
        fallbacks = request_events(segment, request_id, "resource_fallback_not_semantically_admitted")
        failures = request_events(segment, request_id, "request_failed")
        if len(fallbacks) != 1 or fallbacks[0].get("modelCallCount") != 7:
            fail(f"256 request {request_id} requires one seven-call resource fallback event")
        if len(failures) != 1 or failures[0].get("modelCallCount") != 7:
            fail(f"256 request {request_id} requires one seven-call request_failed event")
    print(f"QWEN3_PHYSICAL_JSONL: NON_SEMANTIC_EVIDENCE_ONLY profile=256 requests={len(request_ids)} events={len(segment)}")
    sys.exit(2)
else:
    fail("requested profile must be exactly 1024, 512, or 256")
PY
jsonl_status=$?
set -e

if (( launch_status != 0 )); then
  print -u2 -r -- "QWEN3_PHYSICAL_QUALIFICATION: launch exited $launch_status; JSONL was still copied for diagnosis."
  exit "$launch_status"
fi
if (( jsonl_status == 2 )); then
  print -u2 -r -- "QWEN3_PHYSICAL_QUALIFICATION: NON_SEMANTIC_EVIDENCE_ONLY profile=256; this is not a qualification pass."
  exit 2
fi
(( jsonl_status == 0 )) || exit "$jsonl_status"
print -r -- "QWEN3_PHYSICAL_QUALIFICATION: evidence copied to $evidence_root"
