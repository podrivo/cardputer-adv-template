#!/usr/bin/env bash
# npm run dev — rebuild + flash + monitor when app sources change.
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Kill pid and every descendant (idf.py → idf_monitor → esp_idf_monitor).
kill_tree() {
  local pid="$1"
  local c
  for c in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$c"
  done
  kill "$pid" 2>/dev/null || true
}

serial_port() {
  bash scripts/port.sh
}

wait_port_free() {
  local port="$1"
  local i holders
  for i in $(seq 1 40); do
    if ! lsof "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  holders="$(lsof -t "$port" 2>/dev/null || true)"
  if [[ -n "$holders" ]]; then
    # shellcheck disable=SC2086
    kill $holders 2>/dev/null || true
    sleep 0.5
  fi
}

flash_monitor() {
  local port
  port="$(serial_port)"
  wait_port_free "$port"
  bash scripts/idf.sh -p "$port" flash monitor
}

# Single flash+monitor cycle (used by entr -r so the port is freed first).
if [[ "${1:-}" == "--once" ]]; then
  flash_monitor
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

if command -v entr >/dev/null 2>&1; then
  echo "Watching with entr — save a file under main/ to rebuild + flash + monitor." >&2
  echo "Ctrl+C to stop. (Install not needed — entr found.)" >&2
  while true; do
    # -d: exit when a new file appears so the list refreshes; -r: kill + restart on change
    list_watch_files | entr -d -r bash scripts/watch.sh --once
  done
fi

echo "Watching via poll (install entr for snappier reloads: brew install entr)" >&2
echo "Save under main/ to rebuild + flash + monitor. Ctrl+C to stop." >&2

child=
cleanup() {
  if [[ -n "${child:-}" ]]; then
    kill_tree "$child"
    wait "$child" 2>/dev/null || true
    child=
  fi
  local port
  port="$(serial_port 2>/dev/null || true)"
  if [[ -n "${port:-}" ]]; then
    wait_port_free "$port"
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
    flash_monitor &
    child=$!
  fi
done
