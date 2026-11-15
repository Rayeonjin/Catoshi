#!/usr/bin/env python3
"""Post a public stable release. No third-party packages; never log bot API URLs."""
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = 'Rayeonjin/Catoshi'
ANNOUNCEMENTS = Path(__file__).resolve().parents[1] / 'announcements' / 'telegram'


def message(release, directory=ANNOUNCEMENTS):
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Only published stable releases can be announced.')
    tag = release.get('tag_name', '')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Expected a stable vX.Y.Z tag.')
    path = directory / (tag + '.txt')
    if not path.is_file():
        raise ValueError(f'Missing announcement: announcements/telegram/{tag}.txt')
    text = path.read_text(encoding='utf-8').rstrip('\r\n')
    if not text.strip():
        raise ValueError('Announcement is empty.')
    if len(text.encode('utf-16-le')) // 2 > 4096:
        raise ValueError('Announcement exceeds 4096 UTF-16 units; shorten the source file.')
    required = [f'https://github.com/{REPO}/releases/tag/{tag}',
                'bash setup.sh', 'https://fairy.hada.io/@studio-rayeonjin',
                'https://buymeacoffee.com/rayeonjin', 'https://ko-fi.com/rayeonjin']
    for value in required:
        # Match the complete URL, not a prefix such as v2.16.1 inside v2.16.17.
        if value.startswith('https://'):
            found = value in re.findall(r'https://[^\s]+', text)
        else:
            found = value in text
        if not found:
            raise ValueError(f'Announcement must include: {value}')
    return text


def telegram_request(chat, text, edit_id=''):
    payload = {'chat_id': chat, 'text': text, 'link_preview_options': {'is_disabled': True}}
    if edit_id:
        if not re.fullmatch(r'[1-9][0-9]*', edit_id):
            raise ValueError('EDIT_MESSAGE_ID must be a positive integer; refusing to post.')
        payload['message_id'] = int(edit_id)
        return 'editMessageText', payload
    return 'sendMessage', payload


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
    method, data = telegram_request(chat, text, os.environ.get('EDIT_MESSAGE_ID', ''))
    payload = json.dumps(data).encode()
    request = urllib.request.Request(f'https://api.telegram.org/bot{token}/{method}', data=payload,
                                     headers={'Content-Type': 'application/json'}, method='POST')
    # Never automatically retry a POST: timeout may occur after successful delivery.
    with urllib.request.urlopen(request, timeout=20) as response:
        result = json.load(response)
    if result.get('ok') is not True:
        raise ValueError('Telegram rejected the request. Check bot channel permissions and secrets.')
    verb = 'edited' if method == 'editMessageText' else 'delivered'
    print(f'Telegram announcement {verb}. Message ID:', result['result']['message_id'])


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
