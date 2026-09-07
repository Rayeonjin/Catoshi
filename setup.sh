#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DEST_DIR="${CATOSHI_APPLICATIONS_DIR:-$HOME/Applications}"

if [ "$#" -gt 0 ]; then
  echo "ERROR: setup.sh does not accept build-profile options." >&2
  echo "Usage: ./setup.sh" >&2
  exit 1
fi

"$ROOT/compatibility_check.sh"

echo "== Catoshi v$VERSION =="
echo "macOS 메뉴바에서 BTC와 시장 흐름을 확인하는 작은 고양이입니다."
echo "Swift: $(xcrun swift --version | head -n 1)"
printf '%s/Catoshi.app 으로 빌드하고 설치합니다 ...\n' "$DEST_DIR"
"$ROOT/install_app.sh"

echo
echo "설치 완료. 첫 실행을 확인합니다 ..."
"$ROOT/launch_check.sh" "$DEST_DIR/Catoshi.app"
echo
echo "Catoshi는 Dock이 아니라 macOS 메뉴바에 나타납니다."
echo "로그인 시 자동 실행은 Catoshi의 사용법 탭에서 켤 수 있습니다."
