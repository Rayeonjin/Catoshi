#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Catoshi.app"
BIN="$APP/Contents/MacOS/Catoshi"

if [ -x "$BIN" ]; then
  "$BIN" --unregister-login-item >/dev/null 2>&1 || true
fi
pkill -x Catoshi >/dev/null 2>&1 || true
rm -rf "$APP"

# Remove a pre-v2.13.21 LaunchAgent if one still exists. The app normally migrates
# this automatically, but uninstall should also leave no startup hook behind.
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.local.Catoshi.plist"
if [ -f "$LEGACY_PLIST" ]; then
  launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" >/dev/null 2>&1 || true
  rm -f "$LEGACY_PLIST"
fi

echo "Removed: $APP"
echo "Saved Catoshi preferences were left intact."
echo "To remove preferences too, run: defaults delete com.local.Catoshi"
echo "To remove Activity Radar history too, run: rm -rf \"$HOME/Library/Application Support/Catoshi\""
