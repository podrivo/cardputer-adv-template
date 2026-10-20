#!/usr/bin/env bash
# Load ESP-IDF then run idf.py. Override with IDF_PATH if not at ~/esp/esp-idf.
# Skips export.sh when IDF is already active (faster npm run * loops).
set -euo pipefail

export IDF_CCACHE_ENABLE=1
export ESPBAUD="${ESPBAUD:-921600}"

IDF_ROOT="${IDF_PATH:-$HOME/esp/esp-idf}"

idf_ready() {
  # export.sh sets IDF_PYTHON_ENV_PATH; also accept idf.py already on PATH.
  [[ -n "${IDF_PYTHON_ENV_PATH:-}" ]] && command -v idf.py >/dev/null 2>&1
}

if ! idf_ready; then
  if [[ ! -f "$IDF_ROOT/export.sh" ]]; then
    echo "ESP-IDF not found at $IDF_ROOT — see README prerequisites." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . "$IDF_ROOT/export.sh"
fi

exec idf.py "$@"
