# 텔레그램 릴리스 자동 공지

새 정식 릴리스가 published 상태가 되면 GitHub Actions가 `announcements/telegram/v버전.txt`의 완성 원고를 지정 채널에 게시합니다. 릴리스 설명을 자동으로 가져오지 않습니다. [원고 작성 방법](../announcements/README.md)을 참고해 원고를 먼저 main에 올려 주세요. 앱 버전 변경이나 설치는 필요하지 않습니다. 이미 게시한 릴리스는 자동 소급 전송하지 않습니다.

매 배포 시 담당자는 원고 작성부터 실제 전송 성공 확인까지 수행합니다. [배포 체크리스트](RELEASING.md)를 따르며, 미리보기 성공과 실제 게시 성공을 구분합니다.

## 1. 봇 생성

텔레그램 공식 [@BotFather](https://t.me/BotFather)에서 `/newbot`을 실행합니다. 표시 이름(예: Catoshi 알림)과 `bot`으로 끝나는 사용 가능한 사용자 이름을 정합니다. 발급된 토큰은 비밀번호처럼 보관하고 채팅·코드·스크린샷에 공개하지 마세요.

공지 채널의 관리 메뉴에서 봇을 관리자로 추가하고 메시지 게시 권한을 줍니다. 공개 채널 주소가 `https://t.me/example_channel`이라면 대상 값은 `@example_channel`입니다. 봇 사용자 이름이나 개인 계정 이름을 넣는 것이 아닙니다. 비공개 채널은 `-100…` 형식의 실제 채널 ID가 필요합니다.

## 2. GitHub Secrets

[저장소 Secrets 설정](https://github.com/Rayeonjin/Catoshi/settings/secrets/actions) → New repository secret에서 다음 두 값을 등록합니다.

| Name | Secret |
| --- | --- |
| TELEGRAM_BOT_TOKEN | BotFather가 발급한 봇 토큰 |
| TELEGRAM_CHAT_ID | 공지 채널의 `@사용자이름` 또는 실제 숫자 채널 ID |

경로는 Settings → Secrets and variables → Actions → Secrets입니다. Variables가 아니라 Repository secrets에 등록합니다. 토큰이 노출되면 BotFather에서 폐기·재발급하고 Secret을 교체합니다.

## 3. 미리보기와 첫 게시

[자동 공지 Actions](https://github.com/Rayeonjin/Catoshi/actions/workflows/telegram-release.yml) → Run workflow에서 branch `main`, tag `v2.16.17`, preview_only 체크 상태로 실행합니다. 로그에 공지 초안만 출력하며 텔레그램에 보내지 않습니다. 미리보기에는 텔레그램 Secrets가 필요하지 않습니다.

Secrets와 채널 권한 설정을 마쳤다면 같은 화면에서 새 실행을 시작하고 preview_only 체크를 해제합니다. 이 실행은 실제로 채널에 게시합니다. 이미 공지한 버전을 선택하면 중복 게시되므로 확인 후 실행하세요.

이후 새 정식 릴리스는 자동 게시됩니다. 베타·초안은 제외하며 릴리스 본문 수정은 자동 재게시하지 않습니다. GitHub 토큰으로 다른 Actions에서 릴리스를 생성하는 경우 이벤트 연쇄 실행이 제한될 수 있으므로, 그 배포 방식으로 변경할 때 공지 호출도 연결해야 합니다.

## 실패 확인

Actions에서 실패 원인을 확인합니다. 토큰·대상 Secret 누락, 잘못된 채널 ID, 봇 게시 권한을 우선 점검합니다. 오류 로그에는 토큰이 포함될 수 있는 API URL을 출력하지 않습니다.

전송 요청은 자동 재시도하지 않습니다. 통신 오류가 나도 게시 자체는 성공했을 수 있으므로 채널을 먼저 확인하세요. 같은 실행의 Re-run은 실제 게시를 막습니다. 미게시를 확인한 경우에만 Run workflow로 새 실행을 시작합니다. 수동 실행을 여러 번 만들면 중복 공지가 생길 수 있으며 정확히 한 번 전송을 보장하지는 않습니다.

- [Telegram 봇 생성 안내](https://core.telegram.org/bots/tutorial#obtain-your-bot-token)
- [Telegram sendMessage](https://core.telegram.org/bots/api#sendmessage)
- [GitHub Secrets 안내](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
