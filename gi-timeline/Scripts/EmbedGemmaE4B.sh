#!/bin/zsh

set -euo pipefail

readonly expected_size="3659530240"
readonly expected_sha256="0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
readonly expected_model_mtime_epoch="1704067200"
readonly expected_model_touch_timestamp="202401010000.00"
readonly expected_model_id="litert-community/gemma-4-E4B-it-litert-lm"
readonly expected_revision="28299f30ee4d43294517a4ac93abd6163412f07f"
readonly expected_package_resolved_sha256="90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f"
readonly embed_enabled="${GEMMA_EMBED_ENABLED:-NO}"
readonly output_path="${GEMMA_EMBED_OUTPUT_PATH:?GEMMA_EMBED_OUTPUT_PATH is required}"
readonly receipt_path="${GEMMA_EMBED_RECEIPT_OUTPUT_PATH:?GEMMA_EMBED_RECEIPT_OUTPUT_PATH is required}"

fail() {
  print -u2 -- "error: Gemma E4B embedding failed: $1"
  exit 1
}

file_size() {
  /usr/bin/stat -f "%z" "$1"
}

mtime_epoch() {
  /usr/bin/stat -f "%m" "$1"
}

fingerprint() {
  /usr/bin/stat -f "%d:%i:%z:%m" "$1"
}

file_identity() {
  /usr/bin/stat -f "%d:%i" "$1"
}

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

if [[ "$embed_enabled" != "YES" ]]; then
  /bin/mkdir -p "${output_path:h}" "${receipt_path:h}"
  print -r -- "model embedding disabled for this configuration" > "$output_path"
  print -r -- "status=disabled" > "$receipt_path"
  exit 0
fi

readonly source_path="${GEMMA_E4B_SOURCE:?GEMMA_E4B_SOURCE is required when embedding is enabled}"
readonly package_resolved_path="${SRCROOT:?SRCROOT is required}/GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly source_commit="${GI_SOURCE_COMMIT:-unrecorded}"
readonly source_tree="${GI_SOURCE_TREE:-unrecorded}"

[[ -f "$source_path" && ! -L "$source_path" ]] \
  || fail "source model is missing or is not a regular non-symlink file"
[[ -f "$package_resolved_path" ]] || fail "Package.resolved is missing"
[[ ! -L "$output_path" ]] || fail "existing destination model must not be a symlink"
if [[ -e "$output_path" && ! -f "$output_path" ]]; then
  fail "existing destination model must be a regular file"
fi
[[ ! -L "$receipt_path" ]] || fail "existing model receipt must not be a symlink"
if [[ -e "$receipt_path" && ! -f "$receipt_path" ]]; then
  fail "existing model receipt must be a regular file"
fi
if [[ -e "$output_path" && "$source_path" -ef "$output_path" ]]; then
  fail "source and destination model paths must be distinct files"
fi
readonly package_resolved_sha256="$(sha256 "$package_resolved_path")"
[[ "$package_resolved_sha256" == "$expected_package_resolved_sha256" ]] \
  || fail "Package.resolved SHA-256 does not match the reviewed dependency lock"
if [[ "${CONFIGURATION:-}" == "AppStore" || "${CONFIGURATION:-}" == "PhysicalQualification" ]]; then
  [[ ${#source_commit} == 40 && "$source_commit" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} build requires GI_SOURCE_COMMIT as a 40-character lowercase Git commit"
  [[ ${#source_tree} == 40 && "$source_tree" != *[^0-9a-f]* ]] \
    || fail "${CONFIGURATION} build requires GI_SOURCE_TREE as a 40-character lowercase Git tree"
  "${SRCROOT}/Scripts/ValidateAppSourceCheckout.sh" "${SRCROOT}" "$source_commit" "$source_tree" \
    || fail "${CONFIGURATION} source checkout failed byte-for-HEAD validation before compilation"
fi

readonly source_size="$(file_size "$source_path")"
[[ "$source_size" == "$expected_size" ]] || fail "source model size is ${source_size}; expected ${expected_size} bytes"

readonly source_identity_before="$(file_identity "$source_path")"
readonly source_fingerprint="$(fingerprint "$source_path")"

if [[ -f "$output_path" && ! -L "$output_path" \
  && -f "$receipt_path" && ! -L "$receipt_path" ]]; then
  destination_size="$(file_size "$output_path")"
  destination_fingerprint="$(fingerprint "$output_path")"
  if [[ "$destination_size" == "$expected_size" ]] \
    && [[ "$(mtime_epoch "$output_path")" == "$expected_model_mtime_epoch" ]] \
    && /usr/bin/grep -Fqx "status=verified" "$receipt_path" \
    && /usr/bin/grep -Fqx "model_id=${expected_model_id}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_revision=${expected_revision}" "$receipt_path" \
    && /usr/bin/grep -Fqx "bytes=${expected_size}" "$receipt_path" \
    && /usr/bin/grep -Fqx "sha256=${expected_sha256}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_commit=${source_commit}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_tree=${source_tree}" "$receipt_path" \
    && /usr/bin/grep -Fqx "package_resolved_sha256=${package_resolved_sha256}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_fingerprint=${source_fingerprint}" "$receipt_path" \
    && /usr/bin/grep -Fqx "destination_fingerprint=${destination_fingerprint}" "$receipt_path"; then
    print -- "reused verified embedded model"
    exit 0
  fi
fi

readonly source_sha256="$(sha256 "$source_path")"
[[ "$source_sha256" == "$expected_sha256" ]] || fail "source model SHA-256 does not match the pinned artifact"
[[ -f "$source_path" && ! -L "$source_path" ]] \
  || fail "source model changed type during SHA-256 verification"
[[ "$(file_identity "$source_path")" == "$source_identity_before" ]] \
  || fail "source model was replaced during SHA-256 verification"
[[ "$(file_size "$source_path")" == "$expected_size" ]] \
  || fail "source model size changed during SHA-256 verification"
if [[ -e "$output_path" && "$source_path" -ef "$output_path" ]]; then
  fail "source and destination model paths became the same file during verification"
fi
readonly verified_source_fingerprint="$(fingerprint "$source_path")"

/bin/mkdir -p "${output_path:h}" "${receipt_path:h}"
readonly scratch_root="${TEMP_DIR:-${TMPDIR:-/tmp}}"
[[ -d "$scratch_root" && -w "$scratch_root" ]] \
  || fail "temporary build directory is missing or not writable"
[[ "$(/usr/bin/stat -f '%d' "$scratch_root")" \
  == "$(/usr/bin/stat -f '%d' "${receipt_path:h}")" ]] \
  || fail "temporary build directory and receipt output must share a filesystem"
typeset scratch_model=""
readonly scratch_receipt="$(/usr/bin/mktemp "${scratch_root%/}/GITimeline-Gemma-E4B-receipt.XXXXXX")"
cleanup() {
  if [[ -n "$scratch_model" ]]; then
    /bin/rm -f "$scratch_model"
  fi
  /bin/rm -f "$scratch_receipt"
}
trap cleanup EXIT

typeset reverified_existing_output="NO"
typeset destination_identity_before=""
if [[ -f "$output_path" && ! -L "$output_path" ]] \
  && [[ "$(file_size "$output_path")" == "$expected_size" ]]; then
  destination_identity_before="$(file_identity "$output_path")"
  destination_sha256="$(sha256 "$output_path")"
else
  destination_sha256=""
fi
if [[ "$destination_sha256" == "$expected_sha256" ]]; then
  # Xcode may preserve the exact model bytes while changing only packaging
  # metadata. Reverify those bytes independently before normalizing the mtime;
  # never allocate a second 3.66 GB copy merely to repair deterministic metadata.
  TZ=UTC /usr/bin/touch -t "$expected_model_touch_timestamp" "$output_path"
  [[ -f "$output_path" && ! -L "$output_path" ]] \
    || fail "destination model changed type during metadata normalization"
  [[ "$(file_identity "$output_path")" == "$destination_identity_before" ]] \
    || fail "destination model was replaced during metadata normalization"
  reverified_existing_output="YES"
else
  scratch_model="$(/usr/bin/mktemp "${scratch_root%/}/GITimeline-Gemma-E4B.XXXXXX")"
  # APFS clone-copy avoids requiring a second 3.66 GB allocation during local
  # and archive builds. The destination is still a distinct regular file and
  # every byte is independently hashed below. Fall back to an ordinary copy on
  # filesystems that do not support clones.
  if ! /bin/cp -cf "$source_path" "$scratch_model"; then
    /bin/cp -f "$source_path" "$scratch_model"
  fi
  [[ "$(file_size "$scratch_model")" == "$expected_size" ]] || fail "copied model has the wrong size"
  [[ "$(sha256 "$scratch_model")" == "$expected_sha256" ]] || fail "copied model failed SHA-256 verification"
  TZ=UTC /usr/bin/touch -t "$expected_model_touch_timestamp" "$scratch_model"
  [[ "$(mtime_epoch "$scratch_model")" == "$expected_model_mtime_epoch" ]] \
    || fail "copied model modification time is not deterministic"
  /bin/mv -f "$scratch_model" "$output_path"
  scratch_model=""
fi

[[ -f "$output_path" && ! -L "$output_path" ]] \
  || fail "embedded model is not a regular non-symlink file"
[[ "$(file_size "$output_path")" == "$expected_size" ]] || fail "embedded model has the wrong size"
[[ "$(sha256 "$output_path")" == "$expected_sha256" ]] || fail "embedded model failed SHA-256 verification"
[[ "$(mtime_epoch "$output_path")" == "$expected_model_mtime_epoch" ]] \
  || fail "embedded model modification time is not deterministic"

readonly destination_fingerprint="$(fingerprint "$output_path")"
{
  print -r -- "status=verified"
  print -r -- "model_id=${expected_model_id}"
  print -r -- "source_revision=${expected_revision}"
  print -r -- "bytes=${expected_size}"
  print -r -- "sha256=${expected_sha256}"
  print -r -- "source_commit=${source_commit}"
  print -r -- "source_tree=${source_tree}"
  print -r -- "package_resolved_sha256=${package_resolved_sha256}"
  print -r -- "source_fingerprint=${verified_source_fingerprint}"
  print -r -- "destination_fingerprint=${destination_fingerprint}"
} > "$scratch_receipt"
[[ -f "$scratch_receipt" && ! -L "$scratch_receipt" ]] \
  || fail "model receipt staging file is not a regular non-symlink file"
[[ "$(/usr/bin/wc -l < "$scratch_receipt" | /usr/bin/tr -d ' ')" == "10" ]] \
  || fail "model receipt staging file does not contain ten fields"
[[ "$(/usr/bin/tail -c 1 "$scratch_receipt" | /usr/bin/od -An -tuC | /usr/bin/tr -d ' ')" == "10" ]] \
  || fail "model receipt staging file is not newline terminated"
/bin/mv -f "$scratch_receipt" "$receipt_path"

if [[ "$reverified_existing_output" == "YES" ]]; then
  print -- "reverified existing pinned Gemma E4B model without recopy"
else
  print -- "embedded and verified pinned Gemma E4B model"
fi
