#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly validator_source="${script_directory}/ValidateAppStoreBuild.sh"
readonly scratch_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/GITimeline-manual-fallback-gate.XXXXXX")"
trap '/bin/rm -rf "$scratch_root"' EXIT

fail() {
  print -u2 -- "error: App Store package validation negative test failed: $1"
  exit 1
}

readonly payload_absence_function="$(/usr/bin/sed -n '/^validate_retired_runtime_payload_absence() {$/,/^}$/p' "$validator_source")"
[[ "$payload_absence_function" == validate_retired_runtime_payload_absence\(\)* ]] \
  || fail "could not extract the production retired-runtime payload gate"
eval "$payload_absence_function"

make_app() {
  local case_name="$1"
  local case_root="${scratch_root}/${case_name}/GITimeline.app"
  /bin/mkdir -p "$case_root"
  print -r -- "$case_root"
}

expect_failure() {
  local case_name="$1"
  local expected_marker="$2"
  local case_root="$3"
  local output
  if output="$(validate_retired_runtime_payload_absence "$case_root" 2>&1)"; then
    fail "${case_name} unexpectedly passed"
  fi
  [[ "$output" == *"$expected_marker"* ]] \
    || fail "${case_name} returned the wrong marker: ${output}"
  print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: ${case_name}: ${expected_marker}"
}

good_case="$(make_app good)"
validate_retired_runtime_payload_absence "$good_case" \
  || fail "valid zero-payload control did not pass"
print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: valid zero-payload control"

litert_model_case="$(make_app litert-model)"
print -r -- stray > "${litert_model_case}/stray.litertlm"
expect_failure litert-model "retired generative runtime/model payload is present" "$litert_model_case"

embedded_directory_case="$(make_app embedded-directory)"
/bin/mkdir -p "${embedded_directory_case}/EmbeddedModels"
expect_failure embedded-directory "bundle contains a retired EmbeddedModels directory" "$embedded_directory_case"

embedded_receipt_case="$(make_app embedded-receipt)"
/bin/mkdir -p "${embedded_receipt_case}/EmbeddedModels"
print -r -- stray > "${embedded_receipt_case}/EmbeddedModels/model.receipt"
expect_failure embedded-receipt "bundle contains a retired EmbeddedModels directory" "$embedded_receipt_case"

litert_framework_case="$(make_app litert-framework)"
/bin/mkdir -p "${litert_framework_case}/Frameworks/CLiteRTLM.framework"
print -r -- stray > "${litert_framework_case}/Frameworks/CLiteRTLM.framework/CLiteRTLM"
expect_failure litert-framework "retired generative runtime/model payload is present" "$litert_framework_case"

gemma_marker_case="$(make_app gemma-marker)"
print -r -- stray > "${gemma_marker_case}/gemma-runtime.dat"
expect_failure gemma-marker "retired generative runtime/model payload is present" "$gemma_marker_case"

qwen_marker_case="$(make_app qwen-marker)"
print -r -- stray > "${qwen_marker_case}/qwen-adapter.bin"
expect_failure qwen-marker "retired generative runtime/model payload is present" "$qwen_marker_case"

mlx_marker_case="$(make_app mlx-marker)"
print -r -- stray > "${mlx_marker_case}/mlx-cache.bin"
expect_failure mlx-marker "retired generative runtime/model payload is present" "$mlx_marker_case"

safetensors_case="$(make_app safetensors)"
print -r -- stray > "${safetensors_case}/weights.safetensors"
expect_failure safetensors "retired generative runtime/model payload is present" "$safetensors_case"

gguf_case="$(make_app gguf)"
print -r -- stray > "${gguf_case}/weights.gguf"
expect_failure gguf "retired generative runtime/model payload is present" "$gguf_case"

print -- "MANUAL_FALLBACK_PAYLOAD_TEST: PASS: 10/10 deterministic cases"
