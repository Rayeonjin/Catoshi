#!/bin/bash
set -euo pipefail

FAIL=0
warn() { printf 'WARN: %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*"; FAIL=1; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || printf 'unknown')"

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Catoshi requires macOS."
else
  OS_VERSION="$(sw_vers -productVersion)"
  OS_MAJOR="${OS_VERSION%%.*}"
  ARCH="$(uname -m)"
  printf 'macOS: %s\n' "$OS_VERSION"
  printf 'Architecture: %s\n' "$ARCH"

  if [ "$OS_MAJOR" -lt 13 ]; then
    fail "Catoshi v${APP_VERSION} supports macOS 13 or later."
  fi

  case "$ARCH" in
    arm64|x86_64) ;;
    *) fail "Unsupported Mac architecture: $ARCH" ;;
  esac

  if [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    fail "This shell is running under Rosetta. Reopen Terminal natively before building so Apple-silicon Macs receive an arm64 binary."
  fi
fi

if ! command -v xcrun >/dev/null 2>&1; then
  fail "xcrun was not found. Install current Xcode Command Line Tools and try again."
elif ! SWIFT_BIN="$(xcrun --find swift 2>/dev/null)" || [ -z "$SWIFT_BIN" ]; then
  fail "Apple Swift toolchain was not found through xcrun. Run: xcode-select --install"
else
  if ! SWIFT_LINE="$(xcrun swift --version 2>&1 | head -n 1)"; then
    fail "Apple Swift was found but could not run. Check Xcode/Command Line Tools setup (and the Xcode license if full Xcode is selected)."
    SWIFT_LINE=""
  fi
  SWIFT_VERSION="$(printf '%s\n' "$SWIFT_LINE" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p')"
  [ -z "$SWIFT_LINE" ] || printf 'Swift: %s (%s)\n' "$SWIFT_LINE" "$SWIFT_BIN"
  if [ -n "$SWIFT_VERSION" ]; then
    SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
    SWIFT_MINOR="${SWIFT_VERSION#*.}"
    if [ "$SWIFT_MAJOR" -lt 5 ] || { [ "$SWIFT_MAJOR" -eq 5 ] && [ "$SWIFT_MINOR" -lt 9 ]; }; then
      fail "Swift 5.9 or later is required by this source package. Update Xcode/Command Line Tools."
    fi
  else
    warn "Swift version could not be parsed; the build step will perform the final check."
  fi
fi

if ! command -v xcode-select >/dev/null 2>&1; then
  fail "xcode-select is missing. Install Xcode Command Line Tools."
else
  DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "$DEV_DIR" ]; then
    printf 'Developer tools: %s\n' "$DEV_DIR"
  else
    fail "xcode-select has no active developer directory. Run: xcode-select --install"
  fi
fi

[ -x /usr/libexec/PlistBuddy ] || fail "Required macOS tool is missing: /usr/libexec/PlistBuddy"

for TOOL in plutil sips iconutil codesign ditto lipo; do
  if ! command -v "$TOOL" >/dev/null 2>&1; then
    fail "Required macOS tool is missing: $TOOL"
  fi
done

# SwiftPM release builds and icon generation need temporary working space. Fail early
# with a useful message instead of leaving a half-built app bundle behind.
AVAILABLE_KB="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
if [ -n "$AVAILABLE_KB" ] && [ "$AVAILABLE_KB" -lt 524288 ]; then
  fail "Less than 512 MB of free disk space is available for the build."
elif [ -n "$AVAILABLE_KB" ] && [ "$AVAILABLE_KB" -lt 1048576 ]; then
  warn "Less than 1 GB of free disk space is available; the release build may be tight."
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

printf 'Compatibility preflight: PASS\n'
