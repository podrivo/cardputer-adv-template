#!/usr/bin/env bash
# Watch main/ and fast-rebuild (optionally flash) on change.
# Uses scripts/fast-build.sh (skips ldgen + idf.py). IDF is exported once in this process.
# Usage: watch.sh [build|app-flash]
# Prefers `entr` if installed (`brew install entr`); otherwise polls mtimes.
#
# Agent-friendly: waits until sources settle, never kills an in-flight flash,
# and keeps watching after build/flash failures.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Quiet window before build/flash. Override with WATCH_SETTLE_MS (milliseconds).
SETTLE_MS="${WATCH_SETTLE_MS:-1500}"
export IDF_CCACHE_ENABLE=1
export ESPBAUD="${ESPBAUD:-921600}"

MODE="${1:-app-flash}"
case "$MODE" in
  build|app-flash|--trigger) ;;
  *)
    echo "Usage: $0 [build|app-flash]" >&2
    exit 1
    ;;
esac

# entr / self-invoke: MODE is the second arg
if [[ "$MODE" == "--trigger" ]]; then
  MODE="${2:-app-flash}"
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
    sleep "$(awk "BEGIN { printf \"%.3f\", ${SETTLE_MS}/1000 }")"
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

# Build (and flash) once sources are quiet. Retries if edits arrive mid-build.
# Always returns 0 so entr / the poll loop keep running after failures.
run_once() {
  while true; do
    wait_settled
    local fp
    fp="$(fingerprint)"
    echo "Sources settled — $(action_label)…" >&2

    if ! bash scripts/fast-build.sh; then
      echo "Build failed — still watching for the next change…" >&2
      return 0
    fi

    if [[ "$(fingerprint)" != "$fp" ]]; then
      echo "Sources changed during build — retrying…" >&2
      continue
    fi

    if [[ "$MODE" == "app-flash" ]]; then
      if ! bash scripts/fast-build.sh flash-only; then
        echo "Flash failed — still watching for the next change…" >&2
        return 0
      fi
      if [[ "$(fingerprint)" != "$fp" ]]; then
        echo "Sources changed during flash — rebuilding…" >&2
        continue
      fi
    fi

    return 0
  done
}

# --- entr child entrypoint ---
if [[ "${1:-}" == "--trigger" ]]; then
  ensure_idf
  run_once
  exit 0
fi

# Export IDF once in this long-lived process — entr children inherit the env
# (no 2s export.sh on every save).
ensure_idf
if [[ ! -f build/build.ninja ]]; then
  echo "No build/ yet — one-time idf.py build…" >&2
  bash scripts/idf.sh build
fi

if command -v entr >/dev/null 2>&1; then
  echo "Watching with entr — save under main/ to $(action_label)." >&2
  echo "Settles ${SETTLE_MS}ms before build; Ctrl+C to stop." >&2
  while true; do
    # No -r: never kill an in-flight build/flash when the next save arrives.
    # --trigger always exits 0 so a compile error does not stop the watcher.
    # -d refreshes the file list when new files appear under main/.
    list_watch_files | entr -d bash "$ROOT/scripts/watch.sh" --trigger "$MODE" || true
  done
fi

echo "Watching via poll (install entr for snappier reloads: brew install entr)" >&2
echo "Save under main/ to $(action_label). Settles ${SETTLE_MS}ms. Ctrl+C to stop." >&2

prev="$(fingerprint)"
run_once
prev="$(fingerprint)"

while true; do
  sleep 1
  cur="$(fingerprint)"
  if [[ "$cur" != "$prev" ]]; then
    run_once
    prev="$(fingerprint)"
  fi
done
