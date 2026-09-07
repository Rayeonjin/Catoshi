# Catoshi 설치·업데이트·복구

터미널이나 Swift 빌드를 처음 접하는 Mac 사용자를 위한 가이드입니다. Catoshi는 **비상업적 개인 사용만 허용**하며 회사 내부 업무·기관 활동·고객 작업은 포함하지 않습니다. [LICENSE](../LICENSE)를 확인하세요.

완성된 실행파일을 받는 대신, 공개 릴리스의 소스를 자신의 Mac에서 직접 빌드합니다.

## 준비

- macOS 13 이상, Apple Silicon 또는 Intel Mac
- 인터넷 연결, 약 1 GB 이상의 여유 디스크 공간 권장
- Apple Command Line Tools 및 Swift 5.9 이상

유료 Apple Developer Program, Homebrew, 거래소 API Key는 필요하지 않습니다.

## 1. 릴리스 소스 ZIP 받기

1. [GitHub Releases](https://github.com/Rayeonjin/Catoshi/releases)를 엽니다.
2. 설치할 공개 버전의 릴리스 페이지를 엽니다.
3. Assets의 **Source code (zip)**을 받습니다.
4. ZIP을 더블클릭해 압축을 풉니다.

폴더 이름은 `Catoshi-2.16.5`와 비슷하게 표시될 수 있습니다. 선택한 태그와 폴더 안의 `VERSION` 파일이 같은 버전인지 확인합니다. `Code → Download ZIP`은 기본 브랜치의 최신 개발 소스이므로 재현 가능한 일반 설치에는 릴리스 ZIP을 사용합니다.

## 2. 터미널 열기

`⌘ Command + Space`를 누르고 `터미널` 또는 `Terminal`을 검색해 실행합니다.

## 3. Apple 개발 도구 설치

```bash
xcode-select --install
```

설치 창에서 설치를 누릅니다. `command line tools are already installed`라는 메시지는 이미 준비됐다는 뜻입니다. 설치 후 새 터미널에서 확인합니다.

```bash
xcrun swift --version
```

Swift 버전이 표시되면 다음으로 진행합니다. 보통 전체 Xcode 대신 Command Line Tools만 있으면 됩니다.

## 4. 소스 폴더로 이동

터미널에 `cd `를 입력합니다. `cd` 뒤에 공백을 하나 넣고 Finder에서 압축을 푼 폴더를 터미널 창으로 끌어다 놓은 뒤 Enter를 누릅니다.

예:

```bash
cd /Users/사용자이름/Downloads/Catoshi-2.16.5
```

다음 명령으로 폴더와 버전을 확인할 수 있습니다.

```bash
pwd
cat VERSION
```

## 5. 설치

```bash
chmod +x *.sh
./setup.sh
```

스크립트는 도구·호환성을 확인하고 Swift Release 빌드, 앱 번들 생성, 로컬 ad-hoc 서명과 검증을 수행합니다. 검증된 새 앱을 같은 설치 위치의 임시 경로에 준비한 뒤 `~/Applications/Catoshi.app`으로 교체합니다. 빌드나 사전 검증이 실패하면 기존 설치 앱을 먼저 지우지 않습니다.

처음 빌드는 환경에 따라 시간이 걸릴 수 있습니다. 성공 메시지를 확인한 뒤 화면 위쪽 메뉴바에서 고양이와 가격 또는 데이터 수신 상태를 찾으세요. Catoshi는 Dock에 일반 창을 띄우지 않습니다.

직접 실행:

```bash
open ~/Applications/Catoshi.app
```

앱의 **사용법** 탭에서 로그인 시 자동 실행을 선택할 수 있습니다. macOS가 승인을 요구하면 안내를 따릅니다.

## ZIP으로 설치한 앱 업데이트

1. [Releases](https://github.com/Rayeonjin/Catoshi/releases)에서 새 버전의 변경 내용과 알려진 문제를 확인합니다.
2. 그 버전의 **Source code (zip)**을 받아 **새 폴더**에 풉니다. 기존 소스 폴더에 덮어 풀지 않습니다.
3. 새 폴더로 이동해 `cat VERSION`으로 버전을 확인합니다.
4. 아래 명령을 실행합니다.

```bash
chmod +x *.sh
./setup.sh
```

기존 앱을 먼저 지우거나 `uninstall.sh`를 실행하지 않습니다. 설치가 성공하면 바로 이전 앱 한 개가 `~/Applications/Catoshi.previous.app`에 남습니다. 그다음 성공적인 업데이트 때 이 백업이 교체될 수 있습니다. 오래된 특정 버전을 계속 보관하려면 그 버전의 소스 ZIP과 태그를 따로 보관하세요.

설정은 `com.local.Catoshi` UserDefaults에, Activity Radar의 로컬 기록은 `~/Library/Application Support/Catoshi/`에 저장됩니다. 일반 업데이트와 복구 스크립트는 이 데이터를 지우지 않습니다.

업데이트 뒤 메뉴바·앱 버전, 선택한 표시·고양이 설정, 데이터 수신 상태를 확인하세요. 로그인 자동 실행을 사용한다면 다음 로그인 때 실행되는지도 확인합니다.

## 이전 앱으로 복구

새 버전 설치 후 문제가 있으면 **v2.16.5 이상 소스 폴더에서** 실행합니다.

```bash
./rollback_app.sh
open ~/Applications/Catoshi.app
```

스크립트는 보관된 `~/Applications/Catoshi.previous.app`을 검증한 뒤 현재 앱과 교환합니다. 복구 후 메뉴바와 버전을 확인하고 문제가 있었던 버전·증상을 제보하세요. 현재 앱도 이전 앱 위치에 보관되므로 필요한 경우 같은 스크립트로 다시 교환할 수 있습니다.

백업이 없다면 마지막으로 정상 사용한 버전의 릴리스 소스 ZIP을 별도 폴더에 풀고 그 폴더에서 `./setup.sh`로 다시 설치합니다. 복구를 위해 환경설정이나 Activity Radar 기록을 삭제할 필요는 없습니다.

복구는 앱 실행파일의 버전을 바꿉니다. 과거 시점의 설정·데이터 스냅샷을 복원하지는 않습니다. 앞으로 데이터 형식이 바뀌는 릴리스는 해당 릴리스의 복구 주의사항을 먼저 확인하세요.

## Git을 사용하는 경우

공개된 릴리스 태그를 지정하면 ZIP과 같은 버전의 소스를 받습니다. 예를 들어 `v2.16.5`가 공개된 경우:

```bash
git clone --branch v2.16.5 --depth 1 https://github.com/Rayeonjin/Catoshi.git
cd Catoshi
./setup.sh
```

다음 공개 버전으로 업데이트할 때는 먼저 로컬 변경 여부를 확인합니다.

```bash
git status --short
git fetch --tags origin
```

로컬 수정이 있다면 별도 branch나 복사본에 보관한 뒤 진행합니다. 설치할 실제 공개 태그로 전환하고 빌드합니다.

```bash
git switch --detach v2.16.5
./setup.sh
```

위 태그는 문서 기준 버전 예시입니다. 업데이트 시에는 설치하려는 공개 버전의 정확한 태그로 바꾸세요. 일반 사용자 업데이트에서 `git pull`로 개발 브랜치를 무조건 따라가지 않습니다.

## 앱만 빌드하기

```bash
./build_app.sh
```

`build/Catoshi.app`이 만들어지며 설치 위치의 앱은 교체하지 않습니다. 로컬 개인 사용 산출물입니다. 실행파일의 재배포는 별도 서면 허가가 필요합니다.

## 제거

소스 폴더에서 실행합니다.

```bash
./uninstall.sh
```

설치 앱과 자동 실행 등록을 정리합니다. 설정과 Activity Radar 기록은 기본적으로 유지합니다. 이전 버전 백업을 더 이상 보관하지 않으려면 Finder의 사용자 `Applications` 폴더에서 `Catoshi.previous.app`도 확인해 휴지통으로 옮깁니다.

설정·기록까지 삭제하려면 스크립트가 안내하는 경로와 명령을 먼저 확인하세요. 그 작업은 업데이트나 복구에 필요하지 않습니다.

## 문제가 생겼다면

```bash
./diagnose.sh
```

[문제 해결](TROUBLESHOOTING.md)을 확인한 뒤 해결되지 않으면 [GitHub Issue](https://github.com/Rayeonjin/Catoshi/issues)에 앱 버전·태그, macOS·칩, ZIP/Git 여부, 첫 설치/업데이트/복구 여부, 실행한 명령과 오류 메시지를 적어 주세요. 진단 결과에서 사용자 이름·개인 경로·계정 정보는 지웁니다.
