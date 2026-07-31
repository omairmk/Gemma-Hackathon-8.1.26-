#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")/.." && pwd -P)
export HF_HOME="$ROOT/.hf_cache"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_HUB_DISABLE_TELEMETRY=1
export DO_NOT_TRACK=1
MODEL_KEY=${MODEL_KEY:-e4b}
if [ "${PORT:-8080}" != "8080" ]; then
  echo "Qualifying model launch is fixed to port 8080" >&2
  exit 1
fi
PORT=8080

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

MODEL_PATH=$(
  ROOT="$ROOT" MODEL_KEY="$MODEL_KEY" "$ROOT/.venv/bin/python" -I - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ["ROOT"]).resolve()
spec = json.loads((root / "model_manifest.json").read_text())["models"][os.environ["MODEL_KEY"]]
path = (root / spec["snapshot_path"]).resolve()
if root not in path.parents or not path.is_dir():
    raise SystemExit("Pinned relative snapshot path is missing or unsafe")
print(path)
PY
)
LOG_DIR="$ROOT/.model_logs"
LOG_FILE="$LOG_DIR/model-$PORT.log"
PID_FILE="$LOG_DIR/model-$PORT.pid"
ensure_private_directory "$LOG_DIR"
assert_no_workspace_symlink "$LOG_FILE"
assert_no_workspace_symlink "$PID_FILE"

umask 077
TMP_LOG=$(/usr/bin/mktemp "$LOG_DIR/.model-$PORT.log.XXXXXX")
TMP_PID=$(/usr/bin/mktemp "$LOG_DIR/.model-$PORT.pid.XXXXXX")
PID=
PUBLISHED=0
cleanup_start() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "$PUBLISHED" -ne 1 ] && [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
  fi
  [ -z "$TMP_LOG" ] || [ ! -e "$TMP_LOG" ] || /bin/rm -f -- "$TMP_LOG"
  [ -z "$TMP_PID" ] || [ ! -e "$TMP_PID" ] || /bin/rm -f -- "$TMP_PID"
  exit "$status"
}
trap cleanup_start EXIT
trap 'exit 130' HUP INT TERM

"$ROOT/.venv/bin/mlx_vlm.server" --model "$MODEL_PATH" --host 127.0.0.1 --port "$PORT" >"$TMP_LOG" 2>&1 &
PID=$!
printf '%s\n' "$PID" >"$TMP_PID"
assert_no_workspace_symlink "$LOG_DIR"
assert_no_workspace_symlink "$LOG_FILE"
assert_no_workspace_symlink "$PID_FILE"
/bin/chmod 600 "$TMP_LOG" "$TMP_PID"
/bin/mv -f -- "$TMP_LOG" "$LOG_FILE"
TMP_LOG=
/bin/mv -f -- "$TMP_PID" "$PID_FILE"
TMP_PID=
PUBLISHED=1
trap - EXIT HUP INT TERM
echo "PID=$PID"
echo "MODEL_KEY=$MODEL_KEY"
echo "COMMAND=$ROOT/.venv/bin/mlx_vlm.server --model $MODEL_PATH --host 127.0.0.1 --port $PORT"
echo "Verify complete listener set with: scripts/verify_socket.sh $PID $PORT"
