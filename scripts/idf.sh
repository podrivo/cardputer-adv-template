#!/usr/bin/env bash
# Load ESP-IDF then run idf.py. Override with IDF_PATH if not at ~/esp/esp-idf.
set -euo pipefail
IDF_ROOT="${IDF_PATH:-$HOME/esp/esp-idf}"
if [[ ! -f "$IDF_ROOT/export.sh" ]]; then
  echo "ESP-IDF not found at $IDF_ROOT — see README prerequisites." >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$IDF_ROOT/export.sh"
exec idf.py "$@"
