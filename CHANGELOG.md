# 변경 이력

## v2.16.5 — 2026-09-08

- 비상업적 개인 사용 범위를 명확히 하고 설치·업데이트·복구 안내를 정리했습니다.
- 시장 보조 지표의 수신 실패/갱신 시각을 표시하고 오래된 입력의 자동 해석을 제한합니다.
- CoinGecko 출처 표시와 데이터 제공자별 이용 조건 기록을 보강했습니다.
- 수치 공유 카드를 유지하며 데이터 출처·기준 시각·추정/불완전 상태를 보강합니다.
- 업데이트 전에 새 앱을 검증하고 직전 앱을 보존합니다. `./rollback_app.sh`로 복구할 수 있습니다.

- 국내 자동·수동 갱신 요청을 합치고 이전 응답이 최신값이나 실패 상태를 덮지 않도록 수정했습니다.
- 공유 카드의 긴 시장 요약과 국내 거래소 비중 단위가 잘리지 않도록 개선했습니다.
- Finder·Spotlight에서 실행 중인 앱을 다시 열면 패널을 표시합니다.
- 실행 점검은 요청한 앱의 경로와 동일 PID가 15초 유지되는지 확인합니다.

## v2.16.4 — Community Launch & Telegram Support

- 첫 GitHub + Telegram 공개를 위한 런칭 운영 패키지를 정리했습니다. 앱 런타임 기능은 v2.16.3과 동일하며 버전 메타데이터만 갱신했습니다.
- 앱 내부에는 계속 **GitHub와 Telegram만** 표시하며 Buy Me a Coffee / Ko-fi 후원 링크나 후원 CTA를 넣지 않습니다.
- GitHub README의 `개발 응원하기` 영역에는 Buy Me a Coffee와 Ko-fi 링크를 유지합니다. 후원 여부와 기능·업데이트·사용권 사이에는 차이가 없습니다.
- 모든 향후 공개 릴리스에서 한국어 `TELEGRAM_ANNOUNCEMENT.md`를 필수 생성하도록 운영 규칙을 확정했습니다.
- Telegram 최초 런칭 공지 및 사용자 체감 기능이 있는 주요 릴리스 공지에는 간결한 자발적 후원 footer를 포함합니다. 긴급 hotfix에서도 공지 파일 자체는 반드시 생성하되, 필요하면 후원 footer만 생략할 수 있습니다.
- Telegram 채널 상단 고정용 `TELEGRAM_PINNED_MESSAGE.md`와 운영용 `TELEGRAM_CHANNEL_GUIDE.md`를 추가했습니다.

## v2.16.3 — Community Support Separation

- 앱 정보 화면에서 Buy Me a Coffee 및 후원 안내 문구를 제거했습니다. 앱 안의 외부 채널은 GitHub와 Telegram만 유지합니다.
- 후원 링크는 GitHub README의 `개발 응원하기` 영역에만 둡니다. Buy Me a Coffee를 기본 채널로, Ko-fi를 보조 채널로 제공합니다.
- Catoshi는 무료 소스 공개 프로젝트이며 후원 여부와 기능·업데이트 사이에 차이가 없다는 점을 README에 명시했습니다.
- 공유 카드와 공유 캡션에는 후원 링크를 넣지 않습니다. GitHub/Telegram 유입 구조는 그대로 유지합니다.
- 시장 데이터, Activity Radar, 고양이 동작, 공유 카드 렌더링 및 네트워크 런타임에는 변경이 없습니다.

## v2.16.2 — Community Launch Package

- GitHub + Telegram을 통한 첫 Community 공개를 위한 런칭 패키지를 정리했습니다.
- README에는 현재 버전만 간단히 표시하고, 상세 버전 이력은 `CHANGELOG.md`, 버전별 공식 공지는 GitHub Releases로 분리하는 운영 원칙을 확정했습니다.
- 모든 향후 릴리스에 한국어 Telegram 공지문(`TELEGRAM_ANNOUNCEMENT.md`)을 필수 산출물로 생성하도록 릴리스 규칙을 추가했습니다.
- 다른 컴퓨터/다른 GPT에서도 바로 개발을 이어갈 수 있도록 `NEW_THREAD_START_HERE.md`를 필수 인계 문서로 추가했습니다.
- 집에서 실제 공개를 진행할 수 있도록 `GITHUB_OWNER_GUIDE.md`, `LAUNCH_DAY_GUIDE.md`, `PUBLIC_RELEASE_CHECKLIST.md`를 v2.16.2 기준으로 갱신했습니다.
- 앱 런타임 기능은 v2.16.1과 동일하며, 버전 메타데이터만 v2.16.2로 갱신했습니다.

## v2.16.1 — Telegram Community Channel

- Telegram `https://t.me/Rayeonjin`을 Catoshi의 주요 Community 채널로 복구했습니다.
- 앱 정보 화면의 프로젝트 영역에 Telegram 링크를 추가했습니다. GitHub는 소스/빌드/Issue, Telegram은 공지·업데이트·간단 문의 채널로 역할을 구분합니다.
- 공유 캡션에 Telegram 채널 주소를 함께 넣되 공유 카드 이미지 자체는 기존처럼 간결하게 유지합니다.
- GitHub Issue template의 contact link와 README/CONTRIBUTING 문서에도 Telegram 채널을 반영했습니다.
- Buy Me a Coffee는 앱의 개발 지원 링크로 유지하고 Ko-fi는 README 보조 후원 채널로 유지합니다.
- 빌드 구조, 시장 데이터 런타임, Activity Radar, 고양이 동작, 공유 카드 렌더링 레이아웃은 변경하지 않았습니다.

## v2.16.0 — Community Edition

- Catoshi의 첫 GitHub 공개 준비 버전입니다.
- `internal` / `external` 빌드 프로필을 제거하고 하나의 Community 빌드로 통합했습니다.
- `.app` / `.dmg` 공개 배포 대신 사용자가 자신의 Mac에서 소스를 직접 빌드하는 흐름으로 전환했습니다.
- 앱 정보 화면에 GitHub와 Buy Me a Coffee 링크를 추가했습니다.
- Ko-fi는 README의 보조 후원 채널로만 제공합니다.
- App Store 관련 CTA와 배포 준비 코드를 제거했습니다.
- 공유 카드/캡션의 유입 경로를 Mac App Store가 아닌 GitHub 저장소로 변경했습니다.
- 공유 카드 footer는 Catoshi가 macOS용 무료 소스 공개 프로젝트임을 간결하게 표시합니다.
- 한국어 우선 README, 초보자용 빌드 가이드, 문제 해결, 데이터 출처, 보안, 기여 문서를 추가했습니다.
- GitHub 공개용 `.gitignore`와 Issue template을 추가했습니다.
- 공개 저장소에는 개발 인계, 과거 배포 검토, 비공개 운영 메모, 상세 내부 audit 문서를 포함하지 않습니다.
- Catoshi 고양이 동작, Activity Radar, 시장 데이터 런타임, WebSocket/reconnect 정책은 v2.15.6에서 기능적으로 변경하지 않았습니다.
