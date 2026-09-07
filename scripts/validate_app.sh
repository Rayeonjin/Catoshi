#!/bin/bash
set -euo pipefail

APP="${1:-$HOME/Applications/Catoshi.app}"
BIN="$APP/Contents/MacOS/Catoshi"
PLIST="$APP/Contents/Info.plist"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$APP" ] || fail "App bundle not found: $APP"
[ -x "$BIN" ] || fail "Executable is missing or not executable: $BIN"
[ -f "$PLIST" ] || fail "Info.plist is missing: $PLIST"

plutil -lint "$PLIST" >/dev/null || fail "Info.plist validation failed."

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)"
[ "$BUNDLE_ID" = "com.local.Catoshi" ] || fail "Unexpected bundle identifier: ${BUNDLE_ID:-missing}"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST" 2>/dev/null || true)"
[ "$MIN_OS" = "13.0" ] || fail "Unexpected minimum macOS version in bundle: ${MIN_OS:-missing}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
[ -n "$VERSION" ] || fail "Bundle version is missing."
CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :CatoshiDistributionChannel' "$PLIST" 2>/dev/null || true)"
[ "$CHANNEL" = "community" ] || fail "Unexpected or missing distribution channel: ${CHANNEL:-missing}"
COPYRIGHT_NOTICE="$(/usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' "$PLIST" 2>/dev/null || true)"
[ "$COPYRIGHT_NOTICE" = "© 2026 Rayeonjin. All rights reserved." ] || fail "Copyright metadata does not match the Community build."

HOST_ARCH="$(uname -m)"
ARCHS="$(lipo -archs "$BIN" 2>/dev/null || true)"
case " $ARCHS " in
  *" $HOST_ARCH "*) ;;
  *) fail "Built binary architecture '$ARCHS' does not include host architecture '$HOST_ARCH'." ;;
esac

for atlas in calico cheese gray tuxedo cream; do
  ATLAS="$APP/Contents/Resources/CatoshiAtlas_${atlas}.png"
  [ -f "$ATLAS" ] || fail "Missing sprite atlas: $atlas"
  WIDTH="$(sips -g pixelWidth "$ATLAS" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  HEIGHT="$(sips -g pixelHeight "$ATLAS" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  [ "$WIDTH" = "1624" ] && [ "$HEIGHT" = "40" ] || fail "Unexpected sprite atlas dimensions for $atlas: ${WIDTH:-?}x${HEIGHT:-?}"
done

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || fail "Code-signature verification failed."
fi

printf 'App bundle validation: PASS (%s; v%s; %s; community)\n' "$APP" "$VERSION" "$ARCHS"
