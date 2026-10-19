#!/usr/bin/env bash
# Watch main/ and rebuild (and optionally app-flash) on change.
# Hot path uses ninja (skips idf.py). Usage: watch.sh [build|app-flash]
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEBOUNCE_MS=300
export IDF_CCACHE_ENABLE=1
export ESPBAUD="${ESPBAUD:-921600}"

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

ensure_idf() {
  if [[ -n "${IDF_PYTHON_ENV_PATH:-}" ]] && command -v idf.py >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
    return 0
  fi
  local idf_root="${IDF_PATH:-$HOME/esp/esp-idf}"
  if [[ ! -f "$idf_root/export.sh" ]]; then
    echo "ESP-IDF not found at $idf_root — see README prerequisites." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . "$idf_root/export.sh"
}

ensure_build_dir() {
  if [[ -f build/build.ninja ]]; then
    return 0
  fi
  echo "No build/ yet — one-time idf.py build…" >&2
  bash scripts/idf.sh build
}

debounce() {
  # Absorb bursty multi-file saves before kicking ninja.
  sleep "$(awk "BEGIN { printf \"%.3f\", ${DEBOUNCE_MS}/1000 }")"
}

run_once() {
  debounce
  ensure_idf
  ensure_build_dir
  case "$MODE" in
    build)
      ninja -C build
      ;;
    app-flash)
      # Does not restart monitor. If the port is held by `npm run monitor`,
      # close it first or flash from idf_monitor with Ctrl+T then Ctrl+F.
      ESPPORT="$(bash scripts/port.sh)" ESPBAUD="${ESPBAUD}" ninja -C build app-flash
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

# Wait until fingerprint stops changing (poll path only).
wait_settled() {
  local cur again
  cur="$(fingerprint)"
  while true; do
    sleep "$(awk "BEGIN { printf \"%.3f\", ${DEBOUNCE_MS}/1000 }")"
    again="$(fingerprint)"
    if [[ "$again" == "$cur" ]]; then
      return 0
    fi
    cur="$again"
  done
}

action_label() {
  case "$MODE" in
    build) echo "ninja rebuild" ;;
    app-flash) echo "ninja app-flash @ ${ESPBAUD} baud" ;;
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
    wait_settled
    prev="$(fingerprint)"
    echo "Change detected — $(action_label)…" >&2
    run_once
  fi
done
