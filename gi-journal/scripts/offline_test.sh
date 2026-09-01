#!/bin/sh
# Operator-only Prompt A Wi-Fi-off proof. It requires a previously eligible primary.
set -eu

SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" = "$0" ] && SCRIPT_DIR=.
ROOT=$(CDPATH= cd -P -- "$SCRIPT_DIR/.." && pwd -P)
if [ "${PORT:-8080}" != "8080" ]; then
  echo "Qualifying offline proof is fixed to port 8080" >&2
  exit 1
fi
PORT=8080
PRIMARY_MANIFEST=${PRIMARY_MANIFEST:-$ROOT/primary_runtime_manifest.json}
run_timeout() { /usr/bin/perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$@"; }
ISOLATED_RUNNER='import runpy, sys; root, script, *args = sys.argv[1:]; sys.path[:0] = [root, root + "/scripts"]; sys.argv = [script, *args]; runpy.run_path(script, run_name="__main__")'
valid_pid() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -gt 1 ]
}
assert_no_workspace_symlink() {
  target=$1
  case "$target" in
    "$ROOT"|"$ROOT"/*) ;;
    *) echo "Refusing path outside the workspace: $target" >&2; return 1 ;;
  esac
  current=$ROOT
  [ ! -L "$current" ] || { echo "Refusing symlink path component: $current" >&2; return 1; }
  relative=${target#"$ROOT"}
  relative=${relative#/}
  old_ifs=$IFS
  IFS=/
  set -- $relative
  IFS=$old_ifs
  for component do
    [ -n "$component" ] || continue
    current=$current/$component
    [ ! -L "$current" ] || { echo "Refusing symlink path component: $current" >&2; return 1; }
  done
}
ensure_private_directory() {
  directory=$1
  assert_no_workspace_symlink "$directory"
  if [ -e "$directory" ]; then
    [ -d "$directory" ] || { echo "Expected directory is not a directory: $directory" >&2; return 1; }
  else
    /bin/mkdir -m 700 -- "$directory"
  fi
  assert_no_workspace_symlink "$directory"
}

# This validates the evidence-backed primary before discovering or changing Wi-Fi.
PRIMARY_INFO=$(run_timeout 15 "$ROOT/.venv/bin/python" -I -c "$ISOLATED_RUNNER" "$ROOT" "$ROOT/scripts/primary_manifest.py" --manifest "$PRIMARY_MANIFEST")
PRIMARY=${PRIMARY_INFO%%|*}
PRIMARY_MODEL_PATH=${PRIMARY_INFO#*|}
[ -n "$PRIMARY" ] && [ -n "$PRIMARY_MODEL_PATH" ] && [ "$PRIMARY" != "$PRIMARY_MODEL_PATH" ] || { echo "Invalid primary manifest binding" >&2; exit 1; }
DEV_DIR="$ROOT/.devdata_preflight"
ROUTE_LOG="$DEV_DIR/offline_route_check.txt"
ensure_private_directory "$DEV_DIR"
assert_no_workspace_symlink "$ROUTE_LOG"
WIFI_PORTS=$(run_timeout 15 /usr/sbin/networksetup -listallhardwareports)
WIFI_DEVICE=
found=0
while IFS= read -r line; do
  case "$line" in
    "Hardware Port: Wi-Fi") found=1 ;;
    "Device: "*) if [ "$found" -eq 1 ]; then WIFI_DEVICE=${line#Device: }; break; fi ;;
  esac
done <<EOF
$WIFI_PORTS
EOF
[ -n "$WIFI_DEVICE" ] || { echo "Could not discover Wi-Fi device." >&2; exit 1; }

PID_FILE="$ROOT/.model_logs/model-$PORT.pid"
assert_no_workspace_symlink "$PID_FILE"
OLD_PID=
if [ -f "$PID_FILE" ]; then
  IFS= read -r OLD_PID < "$PID_FILE" || OLD_PID=
  valid_pid "$OLD_PID" || { echo "Refusing malformed server PID file" >&2; exit 1; }
fi

restore_wifi() { run_timeout 30 /usr/sbin/networksetup -setairportpower "$WIFI_DEVICE" on; }
restore_wifi_best_effort() {
  if [ -n "${ROUTE_TMP:-}" ] && [ -e "$ROUTE_TMP" ]; then
    /bin/rm -f -- "$ROUTE_TMP"
  fi
  if ! restore_wifi >/dev/null 2>&1; then
    echo "WARNING: automatic Wi-Fi restoration failed; restore Wi-Fi manually." >&2
  fi
}
abort_offline() {
  trap - EXIT HUP INT TERM
  restore_wifi_best_effort
  exit 130
}
trap restore_wifi_best_effort EXIT
trap abort_offline HUP INT TERM

run_timeout 30 /usr/sbin/networksetup -setairportpower "$WIFI_DEVICE" off
set +e
ROUTE_OUTPUT=$(run_timeout 15 /sbin/route -n get default 2>&1)
ROUTE_STATUS=$?
set -e
assert_no_workspace_symlink "$DEV_DIR"
assert_no_workspace_symlink "$ROUTE_LOG"
umask 077
ROUTE_TMP=$(/usr/bin/mktemp "$DEV_DIR/.offline_route_check.XXXXXX")
{
  printf 'exit_status=%s\n' "$ROUTE_STATUS"
  printf '%s\n' "$ROUTE_OUTPUT"
} > "$ROUTE_TMP"
/bin/chmod 600 "$ROUTE_TMP"
assert_no_workspace_symlink "$DEV_DIR"
assert_no_workspace_symlink "$ROUTE_LOG"
/bin/mv -f -- "$ROUTE_TMP" "$ROUTE_LOG"
ROUTE_TMP=
if ! printf '%s\n' "$ROUTE_OUTPUT" | run_timeout 15 "$ROOT/.venv/bin/python" -I "$ROOT/scripts/server_process.py" --classify-no-route --route-exit-status "$ROUTE_STATUS" >/dev/null; then
  if [ "$ROUTE_STATUS" -eq 0 ]; then
    echo "FAIL: a default route remains (Ethernet, VPN/utun, or tethering may be active)." >&2
  else
    echo "FAIL: unable to establish that the default route is absent." >&2
  fi
  exit 1
fi

if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
  OLD_IDENTITY=$(run_timeout 15 "$ROOT/.venv/bin/python" -I "$ROOT/scripts/server_process.py" --pid "$OLD_PID" --model "$PRIMARY_MODEL_PATH" --port 8080 --identity-json)
  [ -n "$OLD_IDENTITY" ] || { echo "Old server identity proof is empty" >&2; exit 1; }
  kill "$OLD_PID"
fi
MODEL_KEY="$PRIMARY" PORT="$PORT" run_timeout 30 "$ROOT/scripts/start_model.sh"
IFS= read -r NEW_PID < "$PID_FILE" || { echo "Model launcher did not record PID" >&2; exit 1; }
valid_pid "$NEW_PID" || { echo "Model launcher recorded a malformed PID" >&2; exit 1; }
NEW_IDENTITY_BEFORE=$(run_timeout 15 "$ROOT/.venv/bin/python" -I "$ROOT/scripts/server_process.py" --pid "$NEW_PID" --model "$PRIMARY_MODEL_PATH" --port 8080 --identity-json)
[ -n "$NEW_IDENTITY_BEFORE" ] || { echo "New server identity proof is empty" >&2; exit 1; }
attempt=0
while [ "$attempt" -lt 45 ]; do
  if run_timeout 15 "$ROOT/scripts/verify_socket.sh" "$NEW_PID" "$PORT" >/dev/null 2>&1; then break; fi
  attempt=$((attempt + 1))
  run_timeout 2 /bin/sleep 1
done
run_timeout 15 "$ROOT/scripts/verify_socket.sh" "$NEW_PID" "$PORT"
NEW_IDENTITY_AFTER=$(run_timeout 15 "$ROOT/.venv/bin/python" -I "$ROOT/scripts/server_process.py" --pid "$NEW_PID" --model "$PRIMARY_MODEL_PATH" --port 8080 --identity-json)
[ "$NEW_IDENTITY_AFTER" = "$NEW_IDENTITY_BEFORE" ] || { echo "New server identity changed during socket proof" >&2; exit 1; }
run_timeout 150 "$ROOT/.venv/bin/python" -I "$ROOT/scripts/smoke_test_model.py" --offline-one-request --primary-manifest "$PRIMARY_MANIFEST" --base-url "http://127.0.0.1:$PORT" --model-key "$PRIMARY" --pid "$NEW_PID" --evidence "$ROOT/offline_smoke_evidence.json"

# PASS is printed only after restoration succeeds and the resulting state is verified.
restore_wifi
WIFI_STATE=$(run_timeout 15 /usr/sbin/networksetup -getairportpower "$WIFI_DEVICE")
case "$WIFI_STATE" in
  *": On") ;;
  *) echo "FAIL: Wi-Fi restoration could not be verified." >&2; exit 1 ;;
esac
trap - EXIT HUP INT TERM
echo "PASS: no-default-route proof, cold restart, exact PID/process/socket binding, one earned-template request, and verified Wi-Fi restoration completed."
