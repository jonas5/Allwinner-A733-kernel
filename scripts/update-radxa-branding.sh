#!/bin/bash
set -euo pipefail

MNT="${1:-}"
BOARD="${2:-cubie-a7a}"

if [ -z "$MNT" ] || [ ! -d "$MNT/etc" ]; then
  echo "Usage: $0 <mountpoint> [cubie-a7a|cubie-a7s|opi4pro]"
  exit 1
fi

if [ "$BOARD" = "opi4pro" ]; then
  # Orange Pi 4 Pro branding
  BOARD_NAME_FULL="Orange Pi 4 Pro"
  BOARD_SHORT="OPi 4 Pro"
  RELEASE_FILE="$MNT/etc/orangepi-release"
  
  if [ -f "$RELEASE_FILE" ]; then
    sed -i 's/^VERSION=.*/VERSION="1.3.0"/' "$RELEASE_FILE" 2>/dev/null || true
  fi
  exit 0
fi

# Radxa branding
if [ "$BOARD" = "cubie-a7s" ]; then
  MODEL_NAME="Radxa Cubie A7S"
  HOSTNAME_VAL="radxa-cubie-a7s"
  ASCII_TEXT="Radxa Cubie A7S"
else
  MODEL_NAME="Radxa Cubie A7A"
  HOSTNAME_VAL="radxa-cubie-a7a"
  ASCII_TEXT="Radxa Cubie A7A"
fi

VERSION_VAL="1.0.4-beta"

echo "[*] Updating hostname to $HOSTNAME_VAL..."
echo "$HOSTNAME_VAL" > "$MNT/etc/hostname"

if [ -f "$MNT/etc/hosts" ]; then
  sed -i "s/radxa-cubie-a7[as]/$HOSTNAME_VAL/g" "$MNT/etc/hosts"
  sed -i "s/orangepi4pro/$HOSTNAME_VAL/g" "$MNT/etc/hosts"
fi

echo "[*] Updating /etc/os-release and /etc/radxa-release..."
cat << OS_EOF > "$MNT/etc/radxa-release"
BOARD_NAME="$MODEL_NAME"
VERSION="$VERSION_VAL"
BRANCH="edge"
LINUXFAMILY="sun60iw2"
DISTRIBUTION_CODENAME="noble"
OS_EOF

if [ -f "$MNT/etc/orangepi-release" ]; then
  cp -f "$MNT/etc/radxa-release" "$MNT/etc/orangepi-release"
fi

if [ -f "$MNT/etc/os-release" ]; then
  DISTRO_ID=$(grep -E '^ID=' "$MNT/etc/os-release" | cut -d'=' -f2 | tr -d '"' || echo "ubuntu")
  DISTRO_VER=$(grep -E '^VERSION_ID=' "$MNT/etc/os-release" | cut -d'=' -f2 | tr -d '"' || echo "24.04")
  CODENAME=$(grep -E '^VERSION_CODENAME=' "$MNT/etc/os-release" | cut -d'=' -f2 | tr -d '"' || echo "noble")
  
  cat << OS_REL_EOF > "$MNT/etc/os-release"
NAME="Radxa OS"
PRETTY_NAME="Radxa OS $VERSION_VAL (${CODENAME^})"
VERSION="$VERSION_VAL (${CODENAME^})"
VERSION_ID="$DISTRO_VER"
VERSION_CODENAME="$CODENAME"
ID="radxa"
ID_LIKE="$DISTRO_ID debian"
HOME_URL="https://radxa.com"
SUPPORT_URL="https://forum.radxa.com"
BUG_REPORT_URL="https://github.com/radxa"
OS_REL_EOF
fi

echo "[*] Updating /etc/issue and /etc/issue.net..."
printf "$MODEL_NAME ($VERSION_VAL) \\\l\\n\\n" > "$MNT/etc/issue"
printf "$MODEL_NAME ($VERSION_VAL)\\n" > "$MNT/etc/issue.net"

echo "[*] Updating MOTD /etc/update-motd.d/10-orangepi-header with Radxa banner..."
MOTD_HEADER="$MNT/etc/update-motd.d/10-orangepi-header"
if [ -f "$MOTD_HEADER" ]; then
  cat << 'HEADER_EOF' > "$MOTD_HEADER"
#!/bin/bash
THIS_SCRIPT="header"
MOTD_DISABLE=""
[[ -f /etc/default/orangepi-motd ]] && . /etc/default/orangepi-motd
for f in $MOTD_DISABLE; do [[ $f == $THIS_SCRIPT ]] && exit 0; done

. /etc/os-release 2>/dev/null || true
[ -f /etc/radxa-release ] && . /etc/radxa-release 2>/dev/null || true

KERNELID=$(uname -r)

# Radxa ASCII Art Banner
echo -e "\e[1;36m"
cat << 'ASCII_BANNER'
  ____           _               ____      _     _           _ _____ _____ 
 |  _ \ __ _  __| |_  ____ _   / ___|   _| |__ (_) ___      / |___  |___ / 
 | |_) / _` |/ _` \ \/ / _` | | |  | | | | '_ \| |/ _ \_____| |  / /   |_ \ 
 |  _ < (_| | (_| |>  < (_| | | |__| |_| | |_) | |  __/_____| | / /   ___) |
 |_| \_\__,_|\__,_/_/\_\__,_|  \____\__,_|_.__/|_|\___|     |_|/_/   |____/ 
ASCII_BANNER
echo -e "\e[0m"

echo -e "Welcome to \e[1;32m$PRETTY_NAME\e[0m on \e[1;33m$MODEL_NAME\e[0m (Linux $KERNELID)"
echo -e "Hardware: Allwinner A733 (Cortex-A76 + Cortex-A55, NPU 3 TOPS, PowerVR GPU)\n"
HEADER_EOF
  chmod +x "$MOTD_HEADER"
fi

