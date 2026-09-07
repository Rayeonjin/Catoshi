#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$HOME/Applications/Catoshi.app}"

bash "$SCRIPT_DIR/validate_app.sh" "$APP"

# Resolve directory aliases (including /tmp -> /private/tmp) without losing spaces.
canonical_executable() {
  local executable="$1"
  local directory
  directory="$(cd -P "$(dirname "$executable")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$directory" "$(basename "$executable")"
}

EXPECTED_EXECUTABLE="$(canonical_executable "$APP/Contents/MacOS/Catoshi")"

pid_matches_requested_app() {
  local pid="$1"
  local executable
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  executable="$(ps -ww -p "$pid" -o comm= 2>/dev/null)" || return 1
  [ -n "$executable" ] || return 1
  executable="$(canonical_executable "$executable")" || return 1
  [ "$executable" = "$EXPECTED_EXECUTABLE" ]
}

find_requested_pid() {
  local pid
  while IFS= read -r pid; do
    if pid_matches_requested_app "$pid"; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x Catoshi 2>/dev/null || true)
  return 1
}

open -g "$APP"

PID=""
for ((i=1; i<=15; i++)); do
  if PID="$(find_requested_pid)"; then
    break
  fi
  sleep 1
done

# Keep checking the same process and executable, not any process named Catoshi.
# Sixteen observations one second apart cover fifteen seconds of survival.
if [ -n "$PID" ]; then
  for ((i=0; i<=15; i++)); do
    if ! pid_matches_requested_app "$PID"; then
      echo 'ERROR: The requested Catoshi process exited or changed during the 15-second launch check.' >&2
      bash "$SCRIPT_DIR/diagnose.sh" >&2 || true
      exit 1
    fi
    if [ "$i" -lt 15 ]; then sleep 1; fi
  done
  printf 'Launch check: PASS (PID %s; 15 seconds; %s)\n' "$PID" "$EXPECTED_EXECUTABLE"
  exit 0
fi

echo 'ERROR: No running process matched the requested Catoshi bundle after launch.' >&2
bash "$SCRIPT_DIR/diagnose.sh" >&2 || true
exit 1
