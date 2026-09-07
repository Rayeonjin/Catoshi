#!/bin/bash
# Shared by install and rollback. Recovery uses filesystem state, not post-move flags.
set -euo pipefail

replace_catoshi_app() (
  source_app="$1"; destination_dir="$2"; validator="$3"
  current="$destination_dir/Catoshi.app"
  previous="$destination_dir/Catoshi.previous.app"
  lock="$destination_dir/.catoshi-install.lock"
  stage=""

  fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  "$validator" "$source_app"
  mkdir -p "$destination_dir"
  [ ! -L "$current" ] && [ ! -L "$previous" ] || fail "App paths must not be symbolic links."
  mkdir "$lock" 2>/dev/null || fail "Another install or rollback is running ($lock)."

  cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    restore_failed=0
    if [ -n "$stage" ] && [ -f "$stage/transaction-started" ] && [ ! -f "$stage/committed" ]; then
      restore_source=""
      if [ -d "$stage/current.app" ]; then
        restore_source="$stage/current.app"
      elif [ -f "$stage/rotating" ] && [ -d "$previous" ]; then
        # Original current app has already moved into the previous-version slot.
        restore_source="$previous"
      fi
      if [ -n "$restore_source" ]; then
        if [ -e "$current" ]; then
          mv "$current" "$stage/uncommitted.app" || restore_failed=1
        fi
        if [ "$restore_failed" -eq 0 ]; then
          mv "$restore_source" "$current" || restore_failed=1
        fi
      elif [ ! -f "$stage/had-current" ] && [ ! -e "$stage/new.app" ] && [ -e "$current" ]; then
        mv "$current" "$stage/uncommitted.app" || restore_failed=1
      fi
      if [ -d "$stage/older.app" ]; then
        if [ -e "$previous" ]; then restore_failed=1
        else mv "$stage/older.app" "$previous" || restore_failed=1; fi
      fi
    fi
    if [ "$restore_failed" -eq 1 ]; then
      printf 'ERROR: Automatic recovery could not finish. Keep this directory for manual recovery: %s\n' "$stage" >&2
      result=1
    elif [ -n "$stage" ]; then
      rm -rf "$stage"
    fi
    rmdir "$lock" 2>/dev/null || true
    exit "$result"
  }
  trap cleanup EXIT
  trap 'exit 130' HUP INT TERM
  stage="$(mktemp -d "$destination_dir/.catoshi-stage.XXXXXX")"
  /usr/bin/ditto "$source_app" "$stage/new.app"
  "$validator" "$stage/new.app"

  if [ -e "$current" ]; then
    [ -d "$current" ] || fail "Existing app path is not a directory."
    touch "$stage/had-current"
  fi
  touch "$stage/transaction-started"
  # Stop only after the replacement has been copied and validated.
  pkill -x Catoshi >/dev/null 2>&1 || true
  if [ -f "$stage/had-current" ]; then
    mv "$current" "$stage/current.app"
  fi
  mv "$stage/new.app" "$current"
  "$validator" "$current"
  if [ -f "$stage/had-current" ]; then
    # The marker precedes rotation so recovery can recognize every rename boundary.
    touch "$stage/rotating"
    if [ -e "$previous" ]; then mv "$previous" "$stage/older.app"; fi
    mv "$stage/current.app" "$previous"
  fi
  touch "$stage/committed"
  printf 'Installed: %s\n' "$current"
  if [ -d "$previous" ]; then printf 'Previous version: %s\n' "$previous"; fi
  printf 'Personal settings are preserved.\n'
)
