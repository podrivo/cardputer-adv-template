#!/usr/bin/env bash
# Watch main/ and fast-rebuild (optionally flash) on change.
# Uses scripts/fast-build.sh (skips ldgen + idf.py). IDF is exported once in this process.
# Usage: watch.sh [build|app-flash]
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEBOUNCE_MS=300
export IDF_CCACHE_ENABLE=1
export ESPBAUD="${ESPBAUD:-921600}"

MODE="${1:-app-flash}"
case "$MODE" in
  build|app-flash) ;;
  *)
    echo "Usage: $0 [build|app-flash]" >&2
    exit 1
    ;;
esac

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

debounce() {
  sleep "$(awk "BEGIN { printf \"%.3f\", ${DEBOUNCE_MS}/1000 }")"
}

run_once() {
  debounce
  case "$MODE" in
    build)
      bash scripts/fast-build.sh
      ;;
    app-flash)
      bash scripts/fast-build.sh flash
      ;;
  esac
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
    build) echo "fast-build (skip ldgen)" ;;
    app-flash) echo "fast-build + app-flash @ ${ESPBAUD}" ;;
  esac
}

# Export IDF once in this long-lived process — entr children inherit the env
# (no 2s export.sh on every save).
ensure_idf
if [[ ! -f build/build.ninja ]]; then
  echo "No build/ yet — one-time idf.py build…" >&2
  bash scripts/idf.sh build
fi

if command -v entr >/dev/null 2>&1; then
  echo "Watching with entr — save under main/ to $(action_label)." >&2
  echo "Ctrl+C to stop." >&2
  while true; do
    # Run fast-build directly (inherits exported IDF). -d refreshes file list on new files.
    # Do NOT re-enter watch.sh (that used to re-source export.sh every save).
    case "$MODE" in
      build)
        list_watch_files | entr -d -r bash scripts/fast-build.sh
        ;;
      app-flash)
        list_watch_files | entr -d -r bash scripts/fast-build.sh flash
        ;;
    esac
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
