#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${CATOSHI_APPLICATIONS_DIR:-$HOME/Applications}"
DEST_APP="$DEST_DIR/Catoshi.app"

if [ "$#" -gt 0 ]; then
  echo "ERROR: install_app.sh does not accept build-profile options." >&2
  echo "Usage: ./install_app.sh" >&2
  exit 1
fi

"$ROOT/build_app.sh"
source "$ROOT/installation_common.sh"
replace_catoshi_app "$ROOT/build/Catoshi.app" "$DEST_DIR" "$ROOT/validate_app.sh"

printf 'Installed: %s\n' "$DEST_APP"
printf "Run: open '%s'\n" "$DEST_APP"
