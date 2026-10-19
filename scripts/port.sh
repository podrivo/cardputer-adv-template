#!/usr/bin/env bash
# Print serial port: $PORT if set, else first plausible Cardputer ADV USB device.
set -euo pipefail

if [[ -n "${PORT:-}" ]]; then
  printf '%s\n' "$PORT"
  exit 0
fi

shopt -s nullglob
# Stamp-S3 USB Serial/JTAG first, then other USB-serial adapters
for p in /dev/cu.usbmodem* /dev/ttyACM* /dev/cu.wchusbserial* /dev/cu.usbserial* /dev/ttyUSB*; do
  [[ -e "$p" ]] || continue
  echo "Using serial port: $p (set PORT=… to override)" >&2
  printf '%s\n' "$p"
  exit 0
done

if [[ "$(uname -s)" == Linux ]]; then
  fallback=/dev/ttyACM0
else
  fallback=/dev/cu.usbmodem101
fi
echo "No USB serial device found; falling back to $fallback (set PORT=… to override)" >&2
printf '%s\n' "$fallback"
