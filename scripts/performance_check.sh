#!/bin/bash
set -euo pipefail

SAMPLES="${1:-30}"
INTERVAL="${2:-1}"
LABEL="${3:-sample}"
PID="${CATOSHI_PID:-$(pgrep -x Catoshi | head -n 1 || true)}"
WINDOWSERVER_PID="$(pgrep -x WindowServer | head -n 1 || true)"

if [ -z "$PID" ]; then
  echo "Catoshi is not running."
  exit 1
fi
case "$PID" in *[!0-9]*) echo 'CATOSHI_PID must be a process ID.' >&2; exit 2 ;; esac

case "$SAMPLES" in
  ''|*[!0-9]*) echo "SAMPLES must be a positive integer." >&2; exit 2 ;;
esac
if [ "$SAMPLES" -lt 2 ]; then
  echo "SAMPLES must be at least 2." >&2
  exit 2
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
ARCH="$(uname -m)"
RUNNING_PATH="$(ps -p "$PID" -o comm= 2>/dev/null || true)"
APP_PATH="${RUNNING_PATH%/Contents/MacOS/Catoshi}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo unknown)"

printf 'Environment: Catoshi %s | macOS %s | %s | %s\n' "$APP_VERSION" "$OS_VERSION" "$ARCH" "$LABEL"
echo "Sampling Catoshi for ${SAMPLES}x every ${INTERVAL}s..."
printf 'sample  Catoshi CPU%%  RSS(MB)'
if [ -n "$WINDOWSERVER_PID" ]; then printf '  WindowServer CPU%%'; fi
printf '\n'

for ((i=1; i<=SAMPLES; i++)); do
  if ! SAMPLE="$(ps -p "$PID" -o %cpu=,rss= 2>/dev/null | awk 'NF >= 2 {print $1, $2/1024}')" || [ -z "$SAMPLE" ]; then
    echo "Catoshi exited during sampling." >&2
    exit 1
  fi
  read -r C_CPU C_RSS <<< "$SAMPLE"

  W_CPU="0"
  if [ -n "$WINDOWSERVER_PID" ]; then
    W_CPU="$(ps -p "$WINDOWSERVER_PID" -o %cpu= 2>/dev/null | awk '{$1=$1; print}' || true)"
    W_CPU="${W_CPU:-0}"
  fi

  printf '%-7s %-13s %-7.1f' "$i" "$C_CPU" "$C_RSS"
  if [ -n "$WINDOWSERVER_PID" ]; then printf '  %s' "$W_CPU"; fi
  printf '\n'
  printf '%s %s %s\n' "$C_CPU" "$C_RSS" "$W_CPU" >> "$TMP"

  if [ "$i" -lt "$SAMPLES" ]; then sleep "$INTERVAL"; fi
done

quantile() {
  local column="$1"
  local q="$2"
  awk -v c="$column" '{print $c}' "$TMP" | sort -n | awk -v q="$q" '
    { a[NR] = $1 }
    END {
      if (NR == 0) exit 1
      idx = int(NR * q)
      if (idx < NR * q) idx++
      if (idx < 1) idx = 1
      if (idx > NR) idx = NR
      printf "%.2f", a[idx]
    }
  '
}

C_MEDIAN="$(quantile 1 0.50)"
C_P95="$(quantile 1 0.95)"
W_MEDIAN="$(quantile 3 0.50)"
W_P95="$(quantile 3 0.95)"

awk -v cmedian="$C_MEDIAN" -v cp95="$C_P95" -v wmedian="$W_MEDIAN" -v wp95="$W_P95" '
  NR == 1 { firstRSS = $2 }
  {
    cpu += $1
    rss += $2
    ws += $3
    if ($1 > maxCPU) maxCPU = $1
    if ($2 > maxRSS) maxRSS = $2
    if ($3 > maxWS) maxWS = $3
    lastRSS = $2
  }
  END {
    if (NR > 0) {
      printf "\nCatoshi CPU: median %.2f%% | avg %.2f%% | p95 %.2f%% | peak %.2f%%\n", cmedian, cpu/NR, cp95, maxCPU
      printf "Catoshi RSS: avg %.1f MB | max %.1f MB | start %.1f MB | end %.1f MB | delta %+.1f MB\n", rss/NR, maxRSS, firstRSS, lastRSS, lastRSS-firstRSS
      printf "WindowServer CPU: median %.2f%% | avg %.2f%% | p95 %.2f%% | peak %.2f%%\n", wmedian, ws/NR, wp95, maxWS
    }
  }
' "$TMP"

echo
echo "Note: WindowServer is system-wide CPU, not CPU attributable only to Catoshi. Compare the same Mac under similar conditions."
