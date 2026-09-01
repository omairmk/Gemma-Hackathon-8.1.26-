#!/bin/zsh

# Executes the single fresh normalization-policy-bound comparison. Prerequisite:
# an isolated diagnostic bundle is already installed with its frozen manifest
# and 12 sanitized fixtures under FullPrefillNormalizationABV1. The app
# revalidates every manifest/asset hash before analysis. This controller
# neither installs the app nor reads its data container.

set -euo pipefail
umask 077
readonly program_name="${0:t}"

usage() {
  print -u2 -- "Usage: $program_name --udid UDID --bundle-id ID --output NEW_DIR"
  exit 64
}

udid=""
bundle_id=""
output=""
while (( $# > 0 )); do
  case "$1" in
    --udid) (( $# >= 2 )) || usage; udid="$2"; shift 2 ;;
    --bundle-id) (( $# >= 2 )) || usage; bundle_id="$2"; shift 2 ;;
    --output) (( $# >= 2 )) || usage; output="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$udid" && -n "$bundle_id" && -n "$output" ]] || usage
case "$udid" in
  *[!0-9A-Fa-f-]*) usage ;;
esac
case "$bundle_id" in
  *[!A-Za-z0-9.-]*) usage ;;
esac
[[ "$output" == /* && ! -e "$output" && ! -L "$output" ]] || {
  print -u2 -- "Output must be a new absolute path."
  exit 73
}

script_root="${0:A:h}"
evaluator="$script_root/RunFullPrefillNormalizationAB.py"
[[ -f "$evaluator" && ! -L "$evaluator" ]] || exit 66
mkdir -m 700 "$output"
arm140_markers="$output/arm140-terminal-markers.txt"
arm280_markers="$output/arm280-terminal-markers.txt"
: > "$arm140_markers"
: > "$arm280_markers"

fixture_ids=(
  t12-type4-cold-start
  t08-brown-wood-block
  t09-red-capsule
  t10-patterned-rug
  t11-green-smooth-prop
  t06-severe-darkness
  t07-severe-glare
  t05-mixed-hard-loose
  t01-type1-brown-lumps
  t02-type3-cracked-formed
  t03-type5-soft-blobs
  t04-type7-watery-pool
)
arms=(arm140 arm280)
selectors=(
  --internal-gi-v1-photo-full-prefill-normalized-140
  --internal-gi-v1-photo-full-prefill-normalized-280
)
arm_arguments=(
  --run-gi-v1-full-prefill-normalization-ab-140
  --run-gi-v1-full-prefill-normalization-ab-280
)
terminal_pattern='^GI_V1_FULL_PREFILL_NORMALIZATION_AB_(PASS|FAIL) '
integer active_capture_pid=0

cleanup_active_capture() {
  if (( active_capture_pid > 0 )); then
    /usr/bin/xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    wait "$active_capture_pid" >/dev/null 2>&1 || true
    active_capture_pid=0
  fi
}
trap cleanup_active_capture EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Boot only the dedicated target. No install, uninstall, data-container lookup,
# or fixture mutation occurs in this runner.
/usr/bin/xcrun simctl bootstatus "$udid" -b >/dev/null

run_count=0
for arm_index in {1..2}; do
  arm="${arms[$arm_index]}"
  marker_file="$output/${arm}-terminal-markers.txt"
  selector="${selectors[$arm_index]}"
  arm_argument="${arm_arguments[$arm_index]}"
  for fixture_index in {1..12}; do
    fixture="${fixture_ids[$fixture_index]}"
    prefix="$(printf '%s-%02d-%s' "$arm" "$fixture_index" "$fixture")"
    console_path="$output/$prefix.console.log"
    launch_path="$output/$prefix.launch.log"
    : > "$console_path"
    : > "$launch_path"

    /usr/bin/xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    /usr/bin/xcrun simctl launch \
      --terminate-running-process \
      --console \
      "$udid" "$bundle_id" \
      "$selector" \
      "$arm_argument" \
      "--gi-v1-full-prefill-normalization-fixture-$fixture" \
      >"$console_path" 2>>"$launch_path" &
    active_capture_pid=$!
    print -r -- "capture_pid=$active_capture_pid" >> "$launch_path"

    integer deadline=$(( SECONDS + 75 ))
    terminal=""
    while (( SECONDS < deadline )); do
      marker_count="$(/usr/bin/grep -Ec "$terminal_pattern" "$console_path" || true)"
      (( marker_count <= 1 )) || {
        print -u2 -- "Infrastructure stop: duplicate marker for $arm/$fixture."
        exit 70
      }
      if (( marker_count == 1 )); then
        terminal="$(/usr/bin/grep -E "$terminal_pattern" "$console_path")"
        break
      fi
      /bin/kill -0 "$active_capture_pid" >/dev/null 2>&1 || break
      /bin/sleep 0.25
    done
    /usr/bin/xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
    capture_status=0
    wait "$active_capture_pid" || capture_status=$?
    active_capture_pid=0
    print -r -- "capture_status=$capture_status" >> "$launch_path"
    [[ -n "$terminal" ]] || {
      print -u2 -- "Infrastructure stop: no marker for $arm/$fixture."
      exit 70
    }
    print -r -- "$terminal" >> "$marker_file"
    run_count=$((run_count + 1))

    # A semantic/schema/deadline failure disqualifies the arm but does not stop
    # collection. All other failures indicate shared execution corruption.
    if [[ "${terminal%% *}" == "GI_V1_FULL_PREFILL_NORMALIZATION_AB_FAIL" ]]; then
      error_class="$(print -r -- "$terminal" | /usr/bin/awk '
        { for (i = 2; i <= NF; i += 1) if ($i ~ /^error=/) {
            sub(/^error=/, "", $i); print $i; exit
        }}')"
      case "$error_class" in
        fixture_expectation_failed|inference_deadline_exceeded|strict_schema_*) ;;
        *)
          print -u2 -- "Infrastructure stop: $arm/$fixture error=$error_class."
          exit 70
          ;;
      esac
    fi
  done
done

[[ "$run_count" == "24" \
  && "$(/usr/bin/awk 'NF {n += 1} END {print n + 0}' "$arm140_markers")" == "12" \
  && "$(/usr/bin/awk 'NF {n += 1} END {print n + 0}' "$arm280_markers")" == "12" ]] || exit 70

/usr/bin/python3 "$evaluator" \
  --arm-140-markers "$arm140_markers" \
  --arm-280-markers "$arm280_markers" \
  --output "$output/decision.json"
(
  cd "$output"
  /usr/bin/shasum -a 256 -- *.log *-terminal-markers.txt decision.json > SHA256SUMS
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
)
print -r -- "FULL_PREFILL_NORMALIZATION_AB_COMPLETE launches=24 decision=$output/decision.json"
