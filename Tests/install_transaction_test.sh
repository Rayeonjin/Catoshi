#!/bin/bash
# Exercises real directory replacement with a synthetic app and validator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/source.app" "$WORK/Applications"
printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/pkill"
chmod +x "$WORK/bin/pkill"
export PATH="$WORK/bin:$PATH"
cat > "$WORK/validate" <<'VALIDATOR'
#!/bin/bash
set -euo pipefail
[ -f "$1/version" ]
case "${CATOSHI_TEST_FAIL:-}:$1" in
  staged:*/new.app|final:*/Applications/Catoshi.app) exit 1 ;;
esac
VALIDATOR
chmod +x "$WORK/validate"
source "$ROOT/installation_common.sh"
assert_version() { [ "$(cat "$1/version")" = "$2" ] || { echo "Wrong version: $1" >&2; exit 1; }; }
printf '1' > "$WORK/source.app/version"
replace_catoshi_app "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >/dev/null
assert_version "$WORK/Applications/Catoshi.app" 1
[ ! -e "$WORK/Applications/Catoshi.previous.app" ]
printf '2' > "$WORK/source.app/version"
replace_catoshi_app "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >/dev/null
assert_version "$WORK/Applications/Catoshi.app" 2
assert_version "$WORK/Applications/Catoshi.previous.app" 1
# Rolling back swaps the two complete bundles, preserving the ability to undo.
replace_catoshi_app "$WORK/Applications/Catoshi.previous.app" "$WORK/Applications" "$WORK/validate" >/dev/null
assert_version "$WORK/Applications/Catoshi.app" 1
assert_version "$WORK/Applications/Catoshi.previous.app" 2
for failure in staged final; do
  export CATOSHI_TEST_FAIL="$failure"
  if bash -c 'source "$1"; replace_catoshi_app "$2" "$3" "$4"' _ "$ROOT/installation_common.sh" "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >/dev/null 2>&1; then
    echo "Expected $failure failure" >&2; exit 1
  fi
  unset CATOSHI_TEST_FAIL
  assert_version "$WORK/Applications/Catoshi.app" 1
  assert_version "$WORK/Applications/Catoshi.previous.app" 2
  [ ! -d "$WORK/Applications/.catoshi-install.lock" ]
done
# A concurrent transaction must fail without changing either version.
mkdir "$WORK/Applications/.catoshi-install.lock"
if bash -c 'source "$1"; replace_catoshi_app "$2" "$3" "$4"' _ "$ROOT/installation_common.sh" "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >/dev/null 2>&1; then exit 1; fi
assert_version "$WORK/Applications/Catoshi.app" 1
assert_version "$WORK/Applications/Catoshi.previous.app" 2
echo 'PASS: first install, update, rollback, staging failure, final-validation failure, concurrent lock.'
# Inject TERM after each real rename: these are the critical recovery boundaries.
rmdir "$WORK/Applications/.catoshi-install.lock"
cat > "$WORK/bin/mv" <<'MOVE'
#!/bin/bash
set -euo pipefail
if [ "${CATOSHI_TEST_MOVE_FAILURE:-}" = backup ]; then
  case "$1:$2" in
    */current.app:*/Catoshi.previous.app|*/older.app:*/Catoshi.previous.app) exit 1 ;;
  esac
fi
/bin/mv "$@"
case "${CATOSHI_TEST_INTERRUPT:-}:$1:$2" in
  old:*/Catoshi.app:*/current.app|new:*/new.app:*/Catoshi.app|older:*/Catoshi.previous.app:*/older.app|backup:*/current.app:*/Catoshi.previous.app)
    kill -TERM "$PPID" ;;
esac
MOVE
chmod +x "$WORK/bin/mv"
for boundary in old new older backup; do
  export CATOSHI_TEST_INTERRUPT="$boundary"
  if bash -c 'source "$1"; replace_catoshi_app "$2" "$3" "$4"' _ "$ROOT/installation_common.sh" "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >/dev/null 2>&1; then
    echo "Expected interrupt at $boundary" >&2; exit 1
  fi
  unset CATOSHI_TEST_INTERRUPT
  assert_version "$WORK/Applications/Catoshi.app" 1
  assert_version "$WORK/Applications/Catoshi.previous.app" 2
  [ ! -d "$WORK/Applications/.catoshi-install.lock" ]
done
# Failed automatic recovery must retain the older backup and print its location.
export CATOSHI_TEST_MOVE_FAILURE=backup
if bash -c 'source "$1"; replace_catoshi_app "$2" "$3" "$4"' _ "$ROOT/installation_common.sh" "$WORK/source.app" "$WORK/Applications" "$WORK/validate" >"$WORK/recovery.log" 2>&1; then exit 1; fi
unset CATOSHI_TEST_MOVE_FAILURE
assert_version "$WORK/Applications/Catoshi.app" 1
saved_backup=("$WORK/Applications"/.catoshi-stage.*/older.app)
assert_version "${saved_backup[0]}" 2
case "$(cat "$WORK/recovery.log")" in *'manual recovery:'*) ;; *) exit 1;; esac
echo 'PASS: TERM at four rename boundaries; failed backup recovery preserves files.'
