#!/bin/zsh

set -u
set -o pipefail
umask 077

readonly script_path="${0:A}"
readonly runner_path="${script_path:h}/RunPhysicalV4RawPhotoDiagnostic.sh"
temporary_directory=""

fail() {
  print -u2 -r -- "error: physical v4 runner exit-trap test: $1"
  exit 1
}

cleanup() {
  [[ -n "$temporary_directory" && -d "$temporary_directory" ]] || return 0
  /bin/rm -f -- \
    "$temporary_directory/restore-success.marker" \
    "$temporary_directory/restore-failure.marker" \
    "$temporary_directory/restore-not-required.marker" \
    "$temporary_directory/handled.marker"
  /bin/rmdir -- "$temporary_directory" 2>/dev/null || true
}

trap cleanup EXIT INT TERM HUP

[[ -f "$runner_path" && ! -L "$runner_path" ]] || fail "runner is missing or is a symlink"
temporary_directory="$(/usr/bin/mktemp -d /private/tmp/gi-v4-runner-exit-test.XXXXXX)"

run_unhandled_case() {
  local name="$1"
  local restore_required_value="$2"
  local restore_status="$3"
  local expected_status="$4"
  local expected_lines="$5"
  local marker="$temporary_directory/${name}.marker"
  local case_exit_status=0

  GI_PHYSICAL_V4_RUNNER_DEFINITIONS_ONLY=1 \
  GI_RUNNER_PATH="$runner_path" \
  GI_TEST_MARKER="$marker" \
  GI_TEST_RESTORE_REQUIRED="$restore_required_value" \
  GI_TEST_RESTORE_STATUS="$restore_status" \
    /bin/zsh -c '
      source "$GI_RUNNER_PATH"
      restore_normal_launch() {
        print -r -- restore >> "$GI_TEST_MARKER"
        return "$GI_TEST_RESTORE_STATUS"
      }
      cleanup_temporary_directory() {
        print -r -- cleanup >> "$GI_TEST_MARKER"
      }
      restore_required="$GI_TEST_RESTORE_REQUIRED"
      fail_inside_function() { return 23 }
      fail_inside_function
    ' || case_exit_status=$?

  [[ "$case_exit_status" == "$expected_status" ]] \
    || fail "${name} returned ${case_exit_status}; expected ${expected_status}"
  [[ -f "$marker" ]] || fail "${name} did not create its marker"
  [[ "$(/usr/bin/paste -sd, "$marker")" == "$expected_lines" ]] \
    || fail "${name} cleanup order/count drifted"
}

run_unhandled_case restore-success 1 0 23 "restore,cleanup"
run_unhandled_case restore-failure 1 9 1 "restore,cleanup"
run_unhandled_case restore-not-required 0 0 23 "cleanup"

handled_marker="$temporary_directory/handled.marker"
handled_status=0
GI_PHYSICAL_V4_RUNNER_DEFINITIONS_ONLY=1 \
GI_RUNNER_PATH="$runner_path" \
GI_TEST_MARKER="$handled_marker" \
  /bin/zsh -c '
    source "$GI_RUNNER_PATH"
    restore_normal_launch() { print -r -- restore >> "$GI_TEST_MARKER" }
    cleanup_temporary_directory() { print -r -- cleanup >> "$GI_TEST_MARKER" }
    restore_required=1
    handled_failure() { return 23 }
    handled_failure || print -r -- handled >> "$GI_TEST_MARKER"
    exit 0
  ' || handled_status=$?

[[ "$handled_status" == "0" ]] || fail "handled failure returned ${handled_status}"
[[ "$(/usr/bin/paste -sd, "$handled_marker")" == "handled,restore,cleanup" ]] \
  || fail "handled failure triggered cleanup before the explicit exit"

print -r -- "PHYSICAL_V4_RUNNER_EXIT_TRAP_TEST_PASS"
