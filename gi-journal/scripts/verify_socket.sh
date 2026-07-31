#!/bin/sh
# The full listener set for this PID must be exactly one IPv4 loopback socket.
set -eu
PID=${1:?usage: verify_socket.sh PID PORT}
PORT=${2:?usage: verify_socket.sh PID PORT}
case "$PID" in ''|*[!0-9]*) echo "PID must be numeric" >&2; exit 1 ;; esac
[ "$PID" -gt 1 ] || { echo "PID must be greater than 1" >&2; exit 1; }
case "$PORT" in ''|*[!0-9]*) echo "PORT must be numeric" >&2; exit 1 ;; esac
[ "$PORT" -eq 8080 ] || { echo "Qualifying listener proof is fixed to port 8080" >&2; exit 1; }
LISTENERS=$(
  /usr/sbin/lsof -nP -a -p "$PID" -iTCP -sTCP:LISTEN -F nT 2>/dev/null |
    /usr/bin/awk '
      /^n/ { address = substr($0, 2) }
      /^TST=LISTEN$/ && address != "" { print address " (LISTEN)"; address = "" }
    '
)
COUNT=$(printf '%s\n' "$LISTENERS" | /usr/bin/sed '/^$/d' | /usr/bin/wc -l | /usr/bin/tr -d ' ')
if [ "$COUNT" -ne 1 ] || [ "$LISTENERS" != "127.0.0.1:$PORT (LISTEN)" ]; then
  echo "FAIL: PID $PID listener set must be exactly: 127.0.0.1:$PORT (LISTEN)" >&2
  printf '%s\n' "$LISTENERS" >&2
  exit 1
fi
printf '%s\n' "$LISTENERS"
