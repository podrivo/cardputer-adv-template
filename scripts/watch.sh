#!/usr/bin/env bash
# npm run dev — rebuild + flash + monitor when app sources change.
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

flash_monitor() {
  bash scripts/idf.sh -p "$(bash scripts/port.sh)" flash monitor
}

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

if command -v entr >/dev/null 2>&1; then
  echo "Watching with entr — save a file under main/ to rebuild + flash + monitor." >&2
  echo "Ctrl+C to stop. (Install not needed — entr found.)" >&2
  while true; do
    # -d: exit when a new file appears so the list refreshes; -r: kill + restart on change
    list_watch_files | entr -d -r bash scripts/idf.sh -p "$(bash scripts/port.sh)" flash monitor
  done
fi

echo "Watching via poll (install entr for snappier reloads: brew install entr)" >&2
echo "Save under main/ to rebuild + flash + monitor. Ctrl+C to stop." >&2

child=
cleanup() {
  if [[ -n "${child:-}" ]] && kill -0 "$child" 2>/dev/null; then
    kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

prev="$(fingerprint)"
flash_monitor &
child=$!

while true; do
  sleep 2
  cur="$(fingerprint)"
  if [[ "$cur" != "$prev" ]]; then
    prev="$cur"
    echo "Change detected — restarting flash + monitor…" >&2
    cleanup
    child=
    flash_monitor &
    child=$!
  fi
done
