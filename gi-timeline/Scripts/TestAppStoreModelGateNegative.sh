#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly validator_source="${script_directory}/ValidateAppStoreBuild.sh"
readonly scratch_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/GITimeline-model-gate-negative.XXXXXX")"
trap '/bin/rm -rf "$scratch_root"' EXIT

readonly expected_model_id="test/model"
readonly expected_revision="1111111111111111111111111111111111111111"
readonly expected_package_sha256="2222222222222222222222222222222222222222222222222222222222222222"
readonly expected_source_commit="3333333333333333333333333333333333333333"
readonly expected_source_tree="4444444444444444444444444444444444444444"
readonly expected_model_mtime_epoch="1704067200"
readonly expected_model_touch_timestamp="202401010000.00"
readonly good_model_text="pinned-model-fixture"
readonly expected_fixture_size="$(print -r -- "$good_model_text" | /usr/bin/wc -c | /usr/bin/tr -d ' ')"
readonly expected_fixture_sha256="$(print -r -- "$good_model_text" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"

fail() {
  print -u2 -- "error: App Store package validation failed: $1"
  exit 1
}

readonly validator_function="$(/usr/bin/sed -n '/^validate_app_store_model_gate() {$/,/^}$/p' "$validator_source")"
[[ "$validator_function" == validate_app_store_model_gate\(\)* ]] \
  || fail "could not extract the production model gate"
eval "$validator_function"
readonly absence_validator_function="$(/usr/bin/sed -n '/^validate_manual_fallback_payload_absence() {$/,/^}$/p' "$validator_source")"
[[ "$absence_validator_function" == validate_manual_fallback_payload_absence\(\)* ]] \
  || fail "could not extract the production manual fallback payload gate"
eval "$absence_validator_function"

make_case() {
  local case_name="$1"
  local case_root="${scratch_root}/${case_name}/GITimeline.app"
  /bin/mkdir -p "${case_root}/EmbeddedModels"
  print -r -- "$good_model_text" > "${case_root}/EmbeddedModels/gemma-4-E4B-it.litertlm"
  TZ=UTC /usr/bin/touch -t "$expected_model_touch_timestamp" \
    "${case_root}/EmbeddedModels/gemma-4-E4B-it.litertlm"
  print -r -- "$case_root"
}

write_receipt() {
  local case_root="$1"
  local model_path="${case_root}/EmbeddedModels/gemma-4-E4B-it.litertlm"
  local model_size="$(/usr/bin/stat -f '%z' "$model_path")"
  local model_sha256="$(/usr/bin/shasum -a 256 "$model_path" | /usr/bin/awk '{print $1}')"
  {
    print -r -- "status=verified"
    print -r -- "model_id=${expected_model_id}"
    print -r -- "source_revision=${expected_revision}"
    print -r -- "bytes=${model_size}"
    print -r -- "sha256=${model_sha256}"
    print -r -- "source_commit=${expected_source_commit}"
    print -r -- "source_tree=${expected_source_tree}"
    print -r -- "package_resolved_sha256=${expected_package_sha256}"
    print -r -- "source_fingerprint=1:2:${model_size}:3"
    print -r -- "destination_fingerprint=4:5:${model_size}:${expected_model_mtime_epoch}"
  } > "${case_root}/EmbeddedModels/gemma-4-E4B-it.receipt"
}

run_validator() {
  local case_root="$1"
  validate_app_store_model_gate \
    "$case_root" \
    "$expected_fixture_size" \
    "$expected_fixture_sha256" \
    "$expected_model_id" \
    "$expected_revision" \
    "$expected_package_sha256" \
    "$expected_source_commit" \
    "$expected_source_tree" \
    "$expected_model_mtime_epoch"
}

expect_failure() {
  local case_name="$1"
  local expected_marker="$2"
  local case_root="$3"
  local output
  if output="$(run_validator "$case_root" 2>&1)"; then
    fail "${case_name} unexpectedly passed"
  fi
  [[ "$output" == *"$expected_marker"* ]] \
    || fail "${case_name} returned the wrong marker: ${output}"
  print -- "MODEL_GATE_NEGATIVE_TEST: PASS: ${case_name}: ${expected_marker}"
}

good_case="$(make_case good)"
write_receipt "$good_case"
run_validator "$good_case" >/dev/null || fail "valid control did not pass"
print -- "MODEL_GATE_NEGATIVE_TEST: PASS: valid control"

missing_model_case="$(make_case missing-model)"
write_receipt "$missing_model_case"
/bin/rm -f "${missing_model_case}/EmbeddedModels/gemma-4-E4B-it.litertlm"
expect_failure missing-model "bundle must contain exactly one .litertlm model" "$missing_model_case"

wrong_size_case="$(make_case wrong-size)"
write_receipt "$wrong_size_case"
print -rn -- x >> "${wrong_size_case}/EmbeddedModels/gemma-4-E4B-it.litertlm"
expect_failure wrong-size "embedded model size is wrong" "$wrong_size_case"

altered_bytes_case="$(make_case altered-bytes)"
write_receipt "$altered_bytes_case"
print -r -- "pinned-model-fixturE" > "${altered_bytes_case}/EmbeddedModels/gemma-4-E4B-it.litertlm"
expect_failure altered-bytes "embedded model SHA-256 is wrong" "$altered_bytes_case"

wrong_mtime_case="$(make_case wrong-mtime)"
write_receipt "$wrong_mtime_case"
TZ=UTC /usr/bin/touch -t 202401010001.00 \
  "${wrong_mtime_case}/EmbeddedModels/gemma-4-E4B-it.litertlm"
expect_failure wrong-mtime "embedded model modification time is wrong" "$wrong_mtime_case"

wrong_receipt_mtime_case="$(make_case wrong-receipt-mtime)"
write_receipt "$wrong_receipt_mtime_case"
/usr/bin/sed -i '' 's/:1704067200$/:1704067260/' \
  "${wrong_receipt_mtime_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure wrong-receipt-mtime \
  "destination fingerprint receipt is missing or malformed" \
  "$wrong_receipt_mtime_case"

missing_receipt_case="$(make_case missing-receipt)"
expect_failure missing-receipt "model/source receipt is missing or is a symlink" "$missing_receipt_case"

extra_receipt_field_case="$(make_case extra-receipt-field)"
write_receipt "$extra_receipt_field_case"
print -r -- "unexpected=value" >> "${extra_receipt_field_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure extra-receipt-field "model/source receipt does not contain the frozen ten-field record" "$extra_receipt_field_case"

wrong_receipt_hash_case="$(make_case wrong-receipt-hash)"
write_receipt "$wrong_receipt_hash_case"
/usr/bin/sed -i '' 's/^sha256=.*/sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
  "${wrong_receipt_hash_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure wrong-receipt-hash "model/source receipt is missing sha256=${expected_fixture_sha256}" "$wrong_receipt_hash_case"

duplicate_receipt_key_case="$(make_case duplicate-receipt-key)"
write_receipt "$duplicate_receipt_key_case"
/usr/bin/sed -i '' 's/^destination_fingerprint=.*/status=verified/' \
  "${duplicate_receipt_key_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure duplicate-receipt-key "model/source receipt must contain exactly one status field" "$duplicate_receipt_key_case"

malformed_fingerprint_case="$(make_case malformed-fingerprint)"
write_receipt "$malformed_fingerprint_case"
/usr/bin/sed -i '' 's/^source_fingerprint=.*/source_fingerprint=not-a-fingerprint/' \
  "${malformed_fingerprint_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure malformed-fingerprint "source fingerprint receipt is missing or malformed" "$malformed_fingerprint_case"

missing_newline_case="$(make_case missing-newline)"
write_receipt "$missing_newline_case"
/usr/bin/python3 -c 'import pathlib, sys; p = pathlib.Path(sys.argv[1]); p.write_bytes(p.read_bytes().rstrip(b"\n"))' \
  "${missing_newline_case}/EmbeddedModels/gemma-4-E4B-it.receipt"
expect_failure missing-newline "model/source receipt must end with exactly one complete newline-terminated field" "$missing_newline_case"

duplicate_model_case="$(make_case duplicate-model)"
write_receipt "$duplicate_model_case"
/bin/cp "${duplicate_model_case}/EmbeddedModels/gemma-4-E4B-it.litertlm" \
  "${duplicate_model_case}/EmbeddedModels/duplicate.litertlm"
expect_failure duplicate-model "bundle must contain exactly one .litertlm model" "$duplicate_model_case"

renamed_model_case="$(make_case renamed-model)"
write_receipt "$renamed_model_case"
/bin/mv "${renamed_model_case}/EmbeddedModels/gemma-4-E4B-it.litertlm" \
  "${renamed_model_case}/EmbeddedModels/renamed.litertlm"
expect_failure renamed-model "model is not at the reviewed bundle path" "$renamed_model_case"

print -- "MODEL_GATE_NEGATIVE_TEST: PASS: 14/14 deterministic cases"

manual_good="${scratch_root}/manual-good/GITimeline.app"
/bin/mkdir -p "$manual_good"
validate_manual_fallback_payload_absence "$manual_good" \
  || fail "valid manual fallback control did not pass"
print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: valid zero-payload control"

manual_model="${scratch_root}/manual-model/GITimeline.app"
/bin/mkdir -p "$manual_model"
print -r -- stray > "${manual_model}/stray.litertlm"
if output="$(validate_manual_fallback_payload_absence "$manual_model" 2>&1)"; then
  fail "manual fallback stray model unexpectedly passed"
fi
[[ "$output" == *"manual fallback bundle contains a .litertlm model"* ]] \
  || fail "manual fallback stray model returned the wrong marker: ${output}"
print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: stray model rejected"

manual_receipt="${scratch_root}/manual-receipt/GITimeline.app"
/bin/mkdir -p "${manual_receipt}/EmbeddedModels"
print -r -- stray > "${manual_receipt}/EmbeddedModels/gemma-4-E4B-it.receipt"
if output="$(validate_manual_fallback_payload_absence "$manual_receipt" 2>&1)"; then
  fail "manual fallback stray receipt unexpectedly passed"
fi
[[ "$output" == *"manual fallback bundle contains an EmbeddedModels payload"* ]] \
  || fail "manual fallback stray receipt returned the wrong marker: ${output}"
print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: stray receipt rejected"

manual_directory="${scratch_root}/manual-directory/GITimeline.app"
/bin/mkdir -p "${manual_directory}/EmbeddedModels"
if output="$(validate_manual_fallback_payload_absence "$manual_directory" 2>&1)"; then
  fail "manual fallback empty EmbeddedModels directory unexpectedly passed"
fi
[[ "$output" == *"manual fallback bundle contains an EmbeddedModels directory"* ]] \
  || fail "manual fallback directory returned the wrong marker: ${output}"
print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: empty EmbeddedModels directory rejected"
print -- "MODEL_GATE_NEGATIVE_TEST: PASS: 18/18 deterministic cases"
