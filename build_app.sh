#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${VERSION//./}"
BUILD="$ROOT/build"
APP="$BUILD/Catoshi.app"
BIN="$APP/Contents/MacOS/Catoshi"
RES="$APP/Contents/Resources"
ICON_SOURCE="$ROOT/Resources/Catoshi_AppIcon.png"
ICONSET="$BUILD/Catoshi.iconset"
ICNS="$RES/Catoshi.icns"
COPYRIGHT_NOTICE="© 2026 Rayeonjin. All rights reserved."

usage() {
  cat <<'USAGE'
Usage: ./build_app.sh

Builds the single Catoshi Community app for the current Mac.
No internal/external build profiles are used in v2.16.0 or later.
USAGE
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: build_app.sh no longer accepts build profiles or other options." >&2; usage >&2; exit 1 ;;
  esac
fi

"$ROOT/compatibility_check.sh" >/dev/null

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$RES"

cd "$ROOT"
# Always use the Apple toolchain selected by xcode-select. This avoids picking up
# Homebrew/swiftenv Swift accidentally and keeps source builds reproducible across Macs.
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swift build -c release --product Catoshi
SWIFT_BIN_DIR="$(MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swift build -c release --show-bin-path)"
BUILT_EXECUTABLE="$SWIFT_BIN_DIR/Catoshi"
[ -x "$BUILT_EXECUTABLE" ] || { echo "ERROR: SwiftPM output not found: $BUILT_EXECUTABLE" >&2; exit 1; }
cp "$BUILT_EXECUTABLE" "$BIN"
chmod +x "$BIN"

if [ -f "$ICON_SOURCE" ]; then
  cp "$ICON_SOURCE" "$RES/Catoshi_AppIcon.png"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi

for atlas in "$ROOT"/Resources/CatoshiAtlas_*.png; do
  if [ -f "$atlas" ]; then
    cp "$atlas" "$RES/$(basename "$atlas")"
  fi
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Catoshi</string>
    <key>CFBundleExecutable</key>
    <string>Catoshi</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.Catoshi</string>
    <key>CFBundleName</key>
    <string>Catoshi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>
    <string>Catoshi</string>
    <key>CatoshiDistributionChannel</key>
    <string>community</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>$COPYRIGHT_NOTICE</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Local source builds are ad-hoc signed on the user's own Mac. No Developer ID,
# notarization or paid Apple Developer account is required for this source-build flow.
codesign --force --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP" >/dev/null

"$ROOT/validate_app.sh" "$APP"

printf 'Built: %s\n' "$APP"
printf "Run: open '%s'\n" "$APP"
