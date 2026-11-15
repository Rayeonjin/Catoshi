#!/usr/bin/env python3
"""Post a public stable release. No third-party packages; never log bot API URLs."""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = 'Rayeonjin/Catoshi'


def message(release):
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Only published stable releases can be announced.')
    tag = release.get('tag_name', '')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected a stable vX.Y.Z tag.')
    title = release.get('name') or f'Catoshi {tag}'
    body = release.get('body') or '변경 사항은 릴리스 페이지에서 확인하세요.'
    # Plain text avoids Telegram Markdown injection and malformed formatting.
    body = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', r'\1 (\2)', body)
    body = re.sub(r'^#{1,6}\s+', '', body, flags=re.M).replace('**', '').replace('`', '')
    # Leave room for fixed installation and support links, including UTF-16 emoji units.
    def clip(text, limit):
        raw = text.encode('utf-16-le')
        if len(raw) <= limit * 2:
            return text
        return raw[:limit * 2].decode('utf-16-le', errors='ignore').rstrip() + '\n… 자세한 내용은 릴리스에서 확인하세요.'
    return (
        '🐈 ' + clip(title, 180) + '\n\n' + clip(body.strip(), 2600)
        + f'\n\n📦 설치·변경 사항\nhttps://github.com/{REPO}/releases/tag/{tag}'
        + '\n\nSource code (zip)을 새 폴더에 풀고 bash setup.sh를 실행하세요.'
        + '\n직접 빌드 방식 · Command Line Tools 필요 · 전체 Xcode 앱 불필요'
        + '\n비상업적 개인 사용만 허용합니다.'
        + '\n\n☕ 개발 응원하기\nhttps://fairy.hada.io/@catoshi'
    )


def main():
    tag = os.environ.get('RELEASE_TAG', '')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('RELEASE_TAG must be vX.Y.Z.')
    request = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}/releases/tags/{urllib.parse.quote(tag, safe="")}',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'User-Agent': 'Catoshi-release-announcer'})
    with urllib.request.urlopen(request, timeout=20) as response:
        release = json.load(response)
    text = message(release)
    preview = os.environ.get('PREVIEW_ONLY', 'true') == 'true'
    if preview:
        print(text)
        print('\nPreview only: no Telegram message sent.')
        return
    # GitHub reruns can follow a successful delivery with a lost response.
    if int(os.environ.get('GITHUB_RUN_ATTEMPT', '1')) > 1:
        raise ValueError('Posting on a rerun is disabled. Check Telegram first, then start a new manual run if needed.')
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '')
    chat = os.environ.get('TELEGRAM_CHAT_ID', '')
    if not token or not chat:
        raise ValueError('Configure TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID repository secrets first.')
    payload = json.dumps({'chat_id': chat, 'text': text, 'link_preview_options': {'is_disabled': True}}).encode()
    request = urllib.request.Request(f'https://api.telegram.org/bot{token}/sendMessage', data=payload,
                                     headers={'Content-Type': 'application/json'}, method='POST')
    # Never automatically retry a POST: timeout may occur after successful delivery.
    with urllib.request.urlopen(request, timeout=20) as response:
        result = json.load(response)
    if result.get('ok') is not True:
        raise ValueError('Telegram rejected the request. Check bot channel permissions and secrets.')
    print('Telegram announcement delivered. Message ID:', result['result']['message_id'])


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        # HTTPError/URLError can contain the token-bearing request URL.
        print('Request failed. Check GitHub/Telegram availability and bot permissions. '
              'Check the channel before trying again; delivery may have succeeded.', file=sys.stderr)
        sys.exit(1)
