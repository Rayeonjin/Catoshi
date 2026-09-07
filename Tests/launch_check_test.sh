#!/bin/bash
# All process discovery, launch, and wait operations are mocked. No app is run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /private/tmp/catoshi-launch-check.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd -P "$WORK" && pwd -P)"
mkdir -p "$WORK/bin" "$WORK/scripts" "$WORK/Apps With Spaces/Catoshi.app/Contents/MacOS" "$WORK/Other.app/Contents/MacOS"
cp "$ROOT/launch_check.sh" "$WORK/scripts/launch_check.sh"
ln -s "$WORK/Apps With Spaces" "$WORK/alias"
export CATOSHI_TEST_WORK="$WORK"
export CATOSHI_TEST_EXECUTABLE="$WORK/Apps With Spaces/Catoshi.app/Contents/MacOS/Catoshi"
export PATH="$WORK/bin:$PATH"

cat > "$WORK/scripts/validate_app.sh" <<'VALIDATOR'
#!/bin/bash
[ "$CATOSHI_TEST_SCENARIO" != validation_failure ]
VALIDATOR
cat > "$WORK/scripts/diagnose.sh" <<'DIAGNOSE'
#!/bin/bash
echo 'mock diagnostics'
DIAGNOSE
cat > "$WORK/bin/open" <<'OPEN'
#!/bin/bash
printf '%s\n' "$@" > "$CATOSHI_TEST_WORK/open.log"
[ "$CATOSHI_TEST_SCENARIO" != open_failure ]
OPEN
cat > "$WORK/bin/sleep" <<'SLEEP'
#!/bin/bash
set -euo pipefail
[ "$1" = 1 ]
tick="$(cat "$CATOSHI_TEST_WORK/tick")"
printf '%s\n' "$((tick + 1))" > "$CATOSHI_TEST_WORK/tick"
SLEEP
cat > "$WORK/bin/pgrep" <<'PGREP'
#!/bin/bash
set -euo pipefail
tick="$(cat "$CATOSHI_TEST_WORK/tick")"
case "$CATOSHI_TEST_SCENARIO" in
  wrong_app) echo 111 ;;
  delayed) echo 111; if [ "$tick" -ge 3 ]; then echo 222; fi ;;
  replacement) if [ "$tick" -lt 2 ]; then echo 222; else echo 333; fi ;;
  *) echo 222 ;;
esac
PGREP
cat > "$WORK/bin/ps" <<'PS'
#!/bin/bash
set -euo pipefail
pid=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -p ]; then shift; pid="$1"; fi
  shift
done
tick="$(cat "$CATOSHI_TEST_WORK/tick")"
case "$pid" in
  111) printf '%s\n' "$CATOSHI_TEST_WORK/Other.app/Contents/MacOS/Catoshi"; exit 0 ;;
  222)
    case "$CATOSHI_TEST_SCENARIO" in
      exits) if [ "$tick" -ge 1 ]; then exit 1; fi ;;
      replacement) if [ "$tick" -ge 2 ]; then exit 1; fi ;;
      path_change) if [ "$tick" -ge 2 ]; then printf '%s\n' "$CATOSHI_TEST_WORK/Other.app/Contents/MacOS/Catoshi"; exit 0; fi ;;
    esac ;;
  333) [ "$CATOSHI_TEST_SCENARIO" = replacement ] || exit 1 ;;
  *) exit 1 ;;
esac
printf '%s\n' "$CATOSHI_TEST_EXECUTABLE"
PS
chmod +x "$WORK/bin/"* "$WORK/scripts/"*.sh

run_case() {
  local scenario="$1" expected="$2" app="$3" minimum_ticks="$4"
  export CATOSHI_TEST_SCENARIO="$scenario"
  printf '0\n' > "$WORK/tick"
  rm -f "$WORK/open.log"
  local result=0
  bash "$WORK/scripts/launch_check.sh" "$app" > "$WORK/result.log" 2>&1 || result=$?
  if { [ "$expected" = pass ] && [ "$result" -ne 0 ]; } || { [ "$expected" = fail ] && [ "$result" -eq 0 ]; }; then
    cat "$WORK/result.log" >&2
    echo "FAIL: $scenario (exit $result)" >&2
    exit 1
  fi
  if [ "$expected" = pass ]; then
    case "$(cat "$WORK/result.log")" in *'Launch check: PASS (PID 222; 15 seconds;'*) ;; *) exit 1 ;; esac
  fi
  [ "$(cat "$WORK/tick")" -ge "$minimum_ticks" ]
  if [ "$scenario" = validation_failure ]; then
    [ ! -e "$WORK/open.log" ]
  else
    [ "$(sed -n '1p' "$WORK/open.log")" = -g ]
    [ "$(sed -n '2p' "$WORK/open.log")" = "$app" ]
  fi
  printf 'PASS: %s\n' "$scenario"
}

APP="$WORK/Apps With Spaces/Catoshi.app"
run_case spaces pass "$APP" 15
run_case symlink_directory pass "$WORK/alias/Catoshi.app" 15
# macOS's /tmp is an alias of /private/tmp; compare aliases in both directions.
run_case tmp_argument pass "/tmp${APP#/private/tmp}" 15
CATOSHI_TEST_EXECUTABLE="/tmp${CATOSHI_TEST_EXECUTABLE#/private/tmp}"
run_case tmp_process pass "$APP" 15
CATOSHI_TEST_EXECUTABLE="$WORK/Apps With Spaces/Catoshi.app/Contents/MacOS/Catoshi"
run_case delayed pass "$APP" 18
run_case wrong_app fail "$APP" 15
run_case exits fail "$APP" 1
run_case replacement fail "$APP" 2
run_case path_change fail "$APP" 2
run_case validation_failure fail "$APP" 0
run_case open_failure fail "$APP" 0
echo 'PASS: 11 mocked launch scenarios; no application launched or terminated.'
