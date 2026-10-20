#!/usr/bin/env bash
# Fast incremental app build: compile main → link with cached sections.ld → elf2image.
# Skips ESP-IDF ldgen (~4–5s) when only app object contents changed.
#
# Usage:
#   scripts/fast-build.sh           # build app .bin
#   scripts/fast-build.sh flash     # build + app-flash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export IDF_CCACHE_ENABLE=1
export ESPBAUD="${ESPBAUD:-921600}"

DO_FLASH=0
if [[ "${1:-}" == "flash" ]]; then
  DO_FLASH=1
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

ensure_idf

if [[ ! -f build/build.ninja ]]; then
  echo "No build/ yet — one-time idf.py build…" >&2
  bash scripts/idf.sh build
fi

LINK_CMD="$ROOT/build/.fast_link.sh"
BIN_CMD="$ROOT/build/.fast_bin.sh"
STAMP="$ROOT/build/.fast_cmds_stamp"

refresh_cached_cmds() {
  # Capture the real link + elf2image commands once per CMake generation.
  ninja -C build -t commands cardputer_adv_template.elf | tail -1 >"$LINK_CMD"
  # Last line of .bin_timestamp commands is the elf2image pipeline.
  ninja -C build -t commands .bin_timestamp | grep -E 'elf2image' | tail -1 >"$BIN_CMD"
  # Record which build.ninja these came from.
  stat -f '%m' build/build.ninja >"$STAMP" 2>/dev/null || stat -c '%Y' build/build.ninja >"$STAMP"
}

need_refresh=0
if [[ ! -f "$LINK_CMD" || ! -f "$BIN_CMD" || ! -f "$STAMP" ]]; then
  need_refresh=1
else
  cur="$(stat -f '%m' build/build.ninja 2>/dev/null || stat -c '%Y' build/build.ninja)"
  old="$(cat "$STAMP")"
  if [[ "$cur" != "$old" ]]; then
    need_refresh=1
  fi
fi
if [[ "$need_refresh" -eq 1 ]]; then
  echo "Caching link/elf2image commands…" >&2
  refresh_cached_cmds
fi

# 1) Compile only what changed under main/ (+ archive libmain.a). ~0.1s for theme.cpp.
ninja -C build esp-idf/main/libmain.a

# 2) Link using existing sections.ld — do NOT ask ninja for the elf (that re-runs ldgen).
echo "Linking (skip ldgen)…" >&2
(
  cd build
  # shellcheck disable=SC1090
  bash "$LINK_CMD"
)

# 3) elf → .bin
echo "elf2image…" >&2
(
  cd build
  # shellcheck disable=SC1090
  bash "$BIN_CMD"
)

if [[ "$DO_FLASH" -eq 1 ]]; then
  port="$(bash scripts/port.sh)"
  echo "app-flash @ ${ESPBAUD} on ${port}…" >&2
  (
    cd build
    esptool.py --chip esp32s3 -p "$port" -b "$ESPBAUD" \
      --before default_reset --after hard_reset \
      write_flash @"$ROOT/build/flash_app_args"
  )
fi

echo "fast-build done." >&2
