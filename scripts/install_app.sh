#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="${CATOSHI_APPLICATIONS_DIR:-$HOME/Applications}"
DEST_APP="$DEST_DIR/Catoshi.app"

if [ "$#" -gt 0 ]; then
  echo "ERROR: install_app.sh does not accept build-profile options." >&2
  echo "Usage: bash scripts/install_app.sh" >&2
  exit 1
fi

bash "$SCRIPT_DIR/build_app.sh"
source "$SCRIPT_DIR/installation_common.sh"
replace_catoshi_app "$ROOT/build/Catoshi.app" "$DEST_DIR" "$SCRIPT_DIR/validate_app.sh"

printf 'Installed: %s\n' "$DEST_APP"
printf "Run: open '%s'\n" "$DEST_APP"
