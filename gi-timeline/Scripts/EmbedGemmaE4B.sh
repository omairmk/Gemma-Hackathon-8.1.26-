#!/bin/zsh

set -euo pipefail

readonly expected_size="3659530240"
readonly expected_sha256="0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
readonly expected_model_id="litert-community/gemma-4-E4B-it-litert-lm"
readonly expected_revision="28299f30ee4d43294517a4ac93abd6163412f07f"
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

fingerprint() {
  /usr/bin/stat -f "%d:%i:%z:%m" "$1"
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

[[ -f "$source_path" ]] || fail "source model is missing"

readonly source_size="$(file_size "$source_path")"
[[ "$source_size" == "$expected_size" ]] || fail "source model size is ${source_size}; expected ${expected_size} bytes"

readonly source_fingerprint="$(fingerprint "$source_path")"

if [[ -f "$output_path" && -f "$receipt_path" ]]; then
  destination_size="$(file_size "$output_path")"
  destination_fingerprint="$(fingerprint "$output_path")"
  if [[ "$destination_size" == "$expected_size" ]] \
    && /usr/bin/grep -Fqx "status=verified" "$receipt_path" \
    && /usr/bin/grep -Fqx "model_id=${expected_model_id}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_revision=${expected_revision}" "$receipt_path" \
    && /usr/bin/grep -Fqx "bytes=${expected_size}" "$receipt_path" \
    && /usr/bin/grep -Fqx "sha256=${expected_sha256}" "$receipt_path" \
    && /usr/bin/grep -Fqx "source_fingerprint=${source_fingerprint}" "$receipt_path" \
    && /usr/bin/grep -Fqx "destination_fingerprint=${destination_fingerprint}" "$receipt_path"; then
    print -- "reused verified embedded model"
    exit 0
  fi
fi

readonly source_sha256="$(sha256 "$source_path")"
[[ "$source_sha256" == "$expected_sha256" ]] || fail "source model SHA-256 does not match the pinned artifact"

/bin/mkdir -p "${output_path:h}" "${receipt_path:h}"
readonly scratch_root="${TEMP_DIR:-${TMPDIR:-/tmp}}"
readonly scratch_model="$(/usr/bin/mktemp "${scratch_root%/}/GITimeline-Gemma-E4B.XXXXXX")"
readonly scratch_receipt="$(/usr/bin/mktemp "${scratch_root%/}/GITimeline-Gemma-E4B-receipt.XXXXXX")"
trap '/bin/rm -f "$scratch_model" "$scratch_receipt"' EXIT

/bin/cp -f "$source_path" "$scratch_model"
[[ "$(file_size "$scratch_model")" == "$expected_size" ]] || fail "copied model has the wrong size"
[[ "$(sha256 "$scratch_model")" == "$expected_sha256" ]] || fail "copied model failed SHA-256 verification"

/bin/mv -f "$scratch_model" "$output_path"
[[ "$(file_size "$output_path")" == "$expected_size" ]] || fail "embedded model has the wrong size"
[[ "$(sha256 "$output_path")" == "$expected_sha256" ]] || fail "embedded model failed SHA-256 verification"

readonly destination_fingerprint="$(fingerprint "$output_path")"
{
  print -r -- "status=verified"
  print -r -- "model_id=${expected_model_id}"
  print -r -- "source_revision=${expected_revision}"
  print -r -- "bytes=${expected_size}"
  print -r -- "sha256=${expected_sha256}"
  print -r -- "source_fingerprint=${source_fingerprint}"
  print -r -- "destination_fingerprint=${destination_fingerprint}"
} > "$scratch_receipt"
/bin/mv -f "$scratch_receipt" "$receipt_path"

print -- "embedded and verified pinned Gemma E4B model"
