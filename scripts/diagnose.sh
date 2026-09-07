#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Catoshi.app"
BIN="$APP/Contents/MacOS/Catoshi"

echo '== Catoshi diagnostics =='
bash "$SCRIPT_DIR/compatibility_check.sh" || true

echo
if [ -d "$APP" ]; then
  echo "Installed app: $APP"
  /usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null | sed 's/^/Version: /' || true
  file "$BIN" 2>/dev/null || true
  lipo -archs "$BIN" 2>/dev/null | sed 's/^/Architectures: /' || true
  if bash "$SCRIPT_DIR/validate_app.sh" "$APP" >/dev/null 2>&1; then
    echo 'Bundle validation: PASS'
  else
    echo 'Bundle validation: FAIL'
    bash "$SCRIPT_DIR/validate_app.sh" "$APP" || true
  fi
  if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    echo 'Quarantine attribute: present'
  else
    echo 'Quarantine attribute: none'
  fi
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Format|CodeDirectory|Signature)=' || true
else
  echo "Installed app not found at $APP"
fi

echo
PID="$(pgrep -x Catoshi | head -n 1 || true)"
if [ -n "$PID" ]; then
  echo "Running PID: $PID"
  ps -p "$PID" -o pid=,%cpu=,rss=,etime=,command= 2>/dev/null || true
else
  echo 'Catoshi is not currently running.'
fi

echo
echo '== Activity Radar history =='
RADAR_HISTORY="$HOME/Library/Application Support/Catoshi/domestic_activity_history_v1.json"
if [ -f "$RADAR_HISTORY" ]; then
  echo "History file: $RADAR_HISTORY"
  echo "History bytes: $(wc -c < "$RADAR_HISTORY" | tr -d ' ')"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$RADAR_HISTORY" <<'PYRADAR'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        rows = json.load(fh)
except Exception as exc:
    print(f"History parse: FAIL ({exc})")
    raise SystemExit(0)

venues = ("upbit", "bithumb", "coinone", "korbit", "gopax")
complete = 0
coverage = {venue: 0 for venue in venues}
for row in rows:
    values = row.get("values", {}) if isinstance(row, dict) else {}
    present = {key for key in values if key in coverage}
    if len(present) == len(venues):
        complete += 1
    for venue in present:
        coverage[venue] += 1

print(f"Samples: {len(rows)} (complete: {complete}, partial: {len(rows) - complete})")
print("Venue coverage: " + ", ".join(f"{venue}={coverage[venue]}" for venue in venues))
if rows:
    latest = rows[-1].get("timestamp")
    if isinstance(latest, (int, float)):
        # Swift Codable's default Date representation is seconds since 2001-01-01 UTC.
        stamp = datetime.fromtimestamp(latest + 978307200, tz=timezone.utc)
        age = max(0, (datetime.now(timezone.utc) - stamp).total_seconds())
        print(f"Latest sample: {stamp.isoformat()} (age {age / 60:.1f}m)")
    else:
        print(f"Latest sample: {latest}")
PYRADAR
  else
    echo "Samples (approx): $(grep -o '"timestamp"' "$RADAR_HISTORY" | wc -l | tr -d ' ')"
    echo 'python3 not found; venue coverage detail skipped.'
  fi
else
  echo 'History file: not created yet'
fi

echo
for URL in \
  'https://api.binance.com/api/v3/ping' \
  'https://api.upbit.com/v1/market/all?is_details=false'; do
  if curl -LfsS --max-time 5 -o /dev/null "$URL"; then
    echo "Network OK: $URL"
  else
    echo "Network WARN: unable to reach $URL"
  fi
done


echo
echo '== Recent Catoshi diagnostics =='
if command -v log >/dev/null 2>&1; then
  log show --last 5m --style compact --predicate 'process == "Catoshi"' 2>/dev/null | tail -n 40 || true
fi
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$CRASH_DIR" ]; then
  # BSD find on macOS has no -maxdepth. Use shell globs so diagnostics work on a
  # stock Mac without GNU coreutils.
  LATEST_CRASH="$(ls -t "$CRASH_DIR"/Catoshi*.crash "$CRASH_DIR"/Catoshi*.ips 2>/dev/null | head -n 1 || true)"
  if [ -n "$LATEST_CRASH" ]; then
    echo "Latest crash report: $LATEST_CRASH"
  else
    echo 'Crash report: none found'
  fi
fi
