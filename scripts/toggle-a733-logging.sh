#!/bin/bash
# ==============================================================================
# Allwinner A733 Boot Logging Mode Toggle (Silent Splash vs Verbose Debug)
# Can be run directly on the board or from another system pointing to SD mount.
# ==============================================================================
set -euo pipefail

TARGET_ARG="${1:-}"
SECOND_ARG="${2:-}"

TARGET_DIR=""
MODE="toggle"

if [ "$TARGET_ARG" = "silent" ] || [ "$TARGET_ARG" = "verbose" ] || [ "$TARGET_ARG" = "toggle" ]; then
  MODE="$TARGET_ARG"
  if [ -n "$SECOND_ARG" ]; then
    TARGET_DIR="$SECOND_ARG"
  fi
elif [ -d "$TARGET_ARG" ]; then
  TARGET_DIR="$TARGET_ARG"
  if [ "$SECOND_ARG" = "silent" ] || [ "$SECOND_ARG" = "verbose" ] || [ "$SECOND_ARG" = "toggle" ]; then
    MODE="$SECOND_ARG"
  fi
fi

if [ -z "$TARGET_DIR" ]; then
  if [ -d "/boot" ] && ([ -f "/boot/radxaEnv.txt" ] || [ -f "/boot/orangepiEnv.txt" ] || [ -f "/boot/bananapiEnv.txt" ]); then
    TARGET_DIR="/boot"
  fi
fi

if [ -z "$TARGET_DIR" ] || [ ! -d "$TARGET_DIR" ]; then
  echo "Usage: sudo $0 [silent|verbose] [target_boot_dir_or_rootfs]"
  echo "  If run on the live board: sudo $0 silent  OR  sudo $0 verbose"
  echo "  If run on mounted SD card: sudo $0 silent /media/user/rootfs/boot"
  exit 1
fi

if [ -d "$TARGET_DIR/boot" ]; then
  TARGET_DIR="$TARGET_DIR/boot"
fi

ENV_FILE=""
for candidate in radxaEnv.txt orangepiEnv.txt bananapiEnv.txt a733-allwinnerEnv.txt; do
  if [ -f "$TARGET_DIR/$candidate" ]; then
    ENV_FILE="$TARGET_DIR/$candidate"
    break
  fi
done

if [ -z "$ENV_FILE" ]; then
  echo "[-] Error: No Env file (radxaEnv.txt/orangepiEnv.txt/bananapiEnv.txt) found in $TARGET_DIR"
  exit 1
fi

CURRENT_CONSOLE=$(grep -E ^console= "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo "serial")

if [ "$MODE" = "toggle" ]; then
  if [ "$CURRENT_CONSOLE" = "serial" ]; then
    MODE="verbose"
  else
    MODE="silent"
  fi
fi

echo "[*] Target boot directory: $TARGET_DIR"
echo "[*] Desired mode: $MODE"

set_param() {
  local file="$1"
  local key="$2"
  local val="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

for f in "$TARGET_DIR"/*Env.txt; do
  [ -f "$f" ] || continue
  if [ "$MODE" = "silent" ]; then
    echo "[*] Applying SILENT SPLASH mode to $f..."
    set_param "$f" "verbosity" "1"
    set_param "$f" "bootlogo" "true"
    set_param "$f" "console" "serial"
    set_param "$f" "earlycon" "off"
  else
    echo "[*] Applying VERBOSE DEBUG mode to $f..."
    set_param "$f" "verbosity" "7"
    set_param "$f" "bootlogo" "false"
    set_param "$f" "console" "both"
    set_param "$f" "earlycon" "on"
  fi
done

echo "======================================================================"
if [ "$MODE" = "silent" ]; then
  echo "[✓] Silent Splash Mode Configured (UART only):"
  echo "    - Framebuffer (HDMI): Clean animated boot splash without log spam"
  echo "    - Serial (UART0): Receives kernel/systemd logs for headless access"
  echo "    - console=serial (ttyS0,115200 only, NO tty1 in bootargs!)"
  echo "    - verbosity=1 (quiet, loglevel=1, vt.global_cursor_default=0)"
  echo "    - bootlogo=true, earlycon=off"
else
  echo "[✓] Verbose Debug Mode Configured:"
  echo "    - Full kernel and systemd boot messages printed to HDMI and UART0"
  echo "    - console=both (ttyS0,115200 and tty1)"
  echo "    - verbosity=7 (loglevel=7, earlyprintk on UART0)"
  echo "    - bootlogo=false, earlycon=on"
fi
echo "======================================================================"
