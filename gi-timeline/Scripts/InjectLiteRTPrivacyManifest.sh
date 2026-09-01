#!/bin/zsh

set -euo pipefail

readonly enabled="${LITERT_PRIVACY_INJECTION_ENABLED:-NO}"
readonly source_path="${LITERT_PRIVACY_MANIFEST_SOURCE:?LITERT_PRIVACY_MANIFEST_SOURCE is required}"
readonly output_path="${LITERT_PRIVACY_OUTPUT_PATH:?LITERT_PRIVACY_OUTPUT_PATH is required}"

fail() {
  print -u2 -- "error: LiteRT privacy-manifest injection failed: $1"
  exit 1
}

if [[ "$enabled" != "YES" ]]; then
  /bin/mkdir -p "${output_path:h}"
  print -r -- "status=disabled" > "$output_path"
  exit 0
fi

[[ -f "$source_path" ]] || fail "source manifest is missing"
[[ -d "${output_path:h}" ]] || fail "embedded CLiteRTLM.framework is missing"
[[ "${output_path:h:t}" == "CLiteRTLM.framework" ]] \
  || fail "output is not inside CLiteRTLM.framework"
/usr/bin/plutil -lint "$source_path" >/dev/null || fail "source manifest is not a valid property list"

for required_value in \
  NSPrivacyAccessedAPICategoryFileTimestamp C617.1 \
  NSPrivacyAccessedAPICategorySystemBootTime 35F9.1; do
  /usr/bin/grep -Fq "<string>${required_value}</string>" "$source_path" \
    || fail "source manifest is missing ${required_value}"
done

readonly scratch_root="${TEMP_DIR:-${TMPDIR:-/tmp}}"
readonly scratch_manifest="$(/usr/bin/mktemp "${scratch_root%/}/CLiteRTLM-PrivacyInfo.XXXXXX")"
trap '/bin/rm -f "$scratch_manifest"' EXIT

/bin/cp -f "$source_path" "$scratch_manifest"
/usr/bin/plutil -lint "$scratch_manifest" >/dev/null || fail "copied manifest is invalid"
/bin/mv -f "$scratch_manifest" "$output_path"
/usr/bin/plutil -lint "$output_path" >/dev/null || fail "embedded framework manifest is invalid"

print -- "injected validated CLiteRTLM privacy manifest"
