#!/bin/bash
# ==============================================================================
# Allwinner A733 Boot Logging Mode Toggle (Silent Splash vs Verbose Debug)
# Can be run directly on the board or from another system pointing to SD mount.
# ==============================================================================
set -euo pipefail

TARGET_DIR=""
if [ -z "" ]; then
  if [ -d "/boot" ] && ([ -f "/boot/radxaEnv.txt" ] || [ -f "/boot/orangepiEnv.txt" ]); then
    TARGET_DIR="/boot"
  fi
fi

if [ -z "" ] || [ ! -d "" ]; then
  echo "Usage: sudo bash [silent|verbose] [target_boot_dir_or_rootfs]"
  echo "  If run on the live board: sudo bash silent  OR  sudo bash verbose"
  echo "  If run on mounted SD card: sudo bash silent /media/user/rootfs/boot"
  exit 1
fi

MODE="toggle"
# If first arg is a path and second is mode or vice versa:
if [ -d "" ]; then
  TARGET_DIR=""
  MODE="toggle"
elif [ -n "" ] && [ -d "" ]; then
  TARGET_DIR=""
elif [ -n "" ] && [ -d "/boot" ]; then
  TARGET_DIR="/boot"
fi

if [ -d "/boot" ]; then
  TARGET_DIR="/boot"
fi

ENV_FILE=""
for candidate in radxaEnv.txt orangepiEnv.txt a733-allwinnerEnv.txt; do
  if [ -f "/" ]; then
    ENV_FILE="/"
    break
  fi
done

if [ -z "" ]; then
  echo "[-] Error: No Env file (radxaEnv.txt/orangepiEnv.txt) found in "
  exit 1
fi

CURRENT_VERBOSITY=$(grep -E '^verbosity=' "" 2>/dev/null | cut -d'=' -f2 || echo "7")

if [ "" = "toggle" ]; then
  if [ "" -le 3 ] 2>/dev/null; then
    NEW_MODE="verbose"
  else
    NEW_MODE="silent"
  fi
else
  NEW_MODE=""
fi

echo "[*] Selected Target: "

set_param() {
  local file=""
  local key=""
  local val=""
  if grep -q "^=" ""; then
    sed -i "s|^=.*|=|" ""
  else
    echo "=" >> ""
  fi
}

for f in ""/*Env.txt; do
  [ -f "" ] || continue
  if [ "" = "silent" ]; then
    echo "[*] Applying SILENT SPLASH mode to $f..."
    set_param "$f" "verbosity" "1"
    set_param "$f" "bootlogo" "true"
    set_param "$f" "console" "both"
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
if [ "" = "silent" ]; then
  echo "[✓] Silent Splash Mode Configured:"
  echo "    - Framebuffer (HDMI/DP): Clean animated boot splash without log spam"
  echo "    - Serial (UART0): Receives kernel/systemd logs for headless access"
  echo "    - verbosity=1 (quiet, loglevel=1, vt.global_cursor_default=0)"
  echo "    - bootlogo=true, earlycon=off"
else
  echo "[✓] Verbose Debug Mode Configured:"
  echo "    - Full kernel and systemd boot messages printed to HDMI and UART0"
  echo "    - verbosity=7 (loglevel=7, earlyprintk on UART0)"
  echo "    - bootlogo=false, earlycon=on"
fi
echo "======================================================================"
