#!/usr/bin/env bash
# Watch main/ and rebuild (and optionally app-flash) on change.
# Usage: watch.sh [build|app-flash]
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-app-flash}"
case "$MODE" in
  build|app-flash|--once) ;;
  *)
    echo "Usage: $0 [build|app-flash]" >&2
    exit 1
    ;;
esac

# When entr restarts with --once, mode is passed as $2.
if [[ "$MODE" == "--once" ]]; then
  MODE="${2:-app-flash}"
  ONCE=1
else
  ONCE=0
fi

run_once() {
  case "$MODE" in
    build)
      bash scripts/idf.sh build
      ;;
    app-flash)
      # Does not restart monitor. If the port is held by `npm run monitor`,
      # close it first or flash from idf_monitor with Ctrl+T then Ctrl+F.
      bash scripts/idf.sh -p "$(bash scripts/port.sh)" app-flash
      ;;
  esac
}

if [[ "$ONCE" -eq 1 ]]; then
  run_once
  exit $?
fi

list_watch_files() {
  find main -type f \( \
    -name '*.cpp' -o -name '*.c' -o -name '*.h' -o -name '*.hpp' -o -name 'CMakeLists.txt' \
  \) 2>/dev/null
  printf '%s\n' CMakeLists.txt sdkconfig.defaults
}

file_mtime() {
  if stat -f '%m' "$1" >/dev/null 2>&1; then
    stat -f '%m' "$1"
  else
    stat -c '%Y' "$1"
  fi
}

fingerprint() {
  local f max=0 m
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    m="$(file_mtime "$f")"
    if ((m > max)); then
      max=$m
    fi
  done < <(list_watch_files)
  printf '%s\n' "$max"
}

action_label() {
  case "$MODE" in
    build) echo "rebuild" ;;
    app-flash) echo "rebuild + app-flash" ;;
  esac
}

if command -v entr >/dev/null 2>&1; then
  echo "Watching with entr — save under main/ to $(action_label)." >&2
  echo "Ctrl+C to stop." >&2
  while true; do
    # -d: exit when a new file appears so the list refreshes; -r: kill + restart on change
    list_watch_files | entr -d -r bash scripts/watch.sh --once "$MODE"
  done
fi

echo "Watching via poll (install entr for snappier reloads: brew install entr)" >&2
echo "Save under main/ to $(action_label). Ctrl+C to stop." >&2

prev="$(fingerprint)"
run_once

while true; do
  sleep 2
  cur="$(fingerprint)"
  if [[ "$cur" != "$prev" ]]; then
    prev="$cur"
    echo "Change detected — $(action_label)…" >&2
    run_once
  fi
done
