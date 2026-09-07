#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${CATOSHI_APPLICATIONS_DIR:-$HOME/Applications}"
if [ "$#" -gt 0 ]; then echo 'Usage: bash scripts/rollback_app.sh' >&2; exit 2; fi
if [ ! -d "$DEST_DIR/Catoshi.previous.app" ]; then
  echo 'ERROR: No previous version is available. Download an earlier release source and run bash setup.sh.' >&2
  exit 1
fi
source "$SCRIPT_DIR/installation_common.sh"
replace_catoshi_app "$DEST_DIR/Catoshi.previous.app" "$DEST_DIR" "$SCRIPT_DIR/validate_app.sh"
printf "Rollback complete. Run: open '%s/Catoshi.app'\n" "$DEST_DIR"
