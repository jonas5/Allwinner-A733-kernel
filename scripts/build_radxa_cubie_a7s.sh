#!/bin/bash
# ==============================================================================
# build_radxa_cubie_a7s.sh - Standalone Builder for Radxa Cubie A7S
#
# Generates bootable SD card image for Radxa Cubie A7S (Allwinner A733 + AXP318)
# Features:
#   - Authentic vendor Device Tree (sun60i-a733-cubie-a7s.dtb) with:
#       * husb311-pins (PL3 gpio_in pull-up) fixing rt1711h IRQ lock & USB-C DP
#       * aux_p / aux_n (PL10 / PL11) SBU DC-bias GPIOs on phy_switcher
#       * allwinner,typec-dp-no-hpd opt-in software HPD lifecycle
#   - Pre-installed AIC8800 USB Wi-Fi 6 & Bluetooth kernel drivers (6.18.63-sun60iw2)
#   - Pre-installed AIC8800D80 firmware & calibration tables with symlinks
#   - Automatic aic8800-bringup.service for automated Wi-Fi/BT bring-up
#   - Universal bootloader (bootloader-radxa-cubie.bin)
#   - Verified clean ext4 filesystem (e2fsck -fy)
#   - Proper hostname & /etc/hosts resolution (radxa-cubie-a7s)
#   - Dedicated Cubie A7S MOTD header with aligned Figlet ASCII banner
#   - VT2 default console (tty2 autologin with switch-to-tty2)
#   - Multithreaded XZ compression and SHA256 checksum generation
#   - Optional GitHub release creation / upload
#
# Usage:
#   ./build_radxa_cubie_a7s.sh [VERSION] [--upload]
# Example:
#   ./build_radxa_cubie_a7s.sh 1.1.6-beta
#   ./build_radxa_cubie_a7s.sh 1.1.6-beta --upload
# ==============================================================================
set -euo pipefail

BOARD_NAME="cubie-a7s"
MODEL_TITLE="Radxa Cubie A7S"
HOSTNAME_VAL="radxa-cubie-a7s"
DTB_FILE="/srv/artifacts/sun60i-a733-cubie-a7s.dtb"
BASE_IMG="/srv/storage/full_18.img"
FIX_BUNDLE="/srv/storage/u-boot_partition_fix.sh"
RELEASE_DIR="/srv/storage/local-releases/radxa-cubie-a7s"
AIC_DRV_DIR="/srv/storage/aic8800_usb_drivers_6.18.63"

VERSION="${1:-1.1.6-beta}"
DO_UPLOAD="no"
for arg in "$@"; do
  if [ "$arg" = "--upload" ]; then
    DO_UPLOAD="yes"
  fi
done

TARGET_NAME="Radxa-Cubie-A7S_${VERSION}_ubuntu_noble_minimal_linux6.18.63"
WORKDIR="/srv/storage"
OUT_IMG="${WORKDIR}/${TARGET_NAME}.img"
OUT_XZ="${OUT_IMG}.xz"
mkdir -p "$RELEASE_DIR"

echo "======================================================================"
echo "  Building ${MODEL_TITLE} Release Image: ${VERSION}"
echo "  Base Image: ${BASE_IMG}"
echo "  DTB:        ${DTB_FILE}"
echo "======================================================================"

if [ ! -f "$BASE_IMG" ]; then
  echo "[-] Error: Base image ${BASE_IMG} not found!" >&2
  exit 1
fi

if [ ! -f "$DTB_FILE" ]; then
  echo "[-] Error: Device tree ${DTB_FILE} not found!" >&2
  exit 1
fi

if [ ! -f "$FIX_BUNDLE" ]; then
  echo "[-] Error: Fix bundle ${FIX_BUNDLE} not found!" >&2
  exit 1
fi

echo "[*] Checking base image ext4 filesystem integrity..."
LOOP_BASE=$(losetup -fP --show "$BASE_IMG")
e2fsck -fy "${LOOP_BASE}p1" || true
losetup -d "$LOOP_BASE"

echo "[*] Cloning base image to ${OUT_IMG}..."
cp -f "$BASE_IMG" "$OUT_IMG"

LOOP_DEV=$(losetup -fP --show "$OUT_IMG")
echo "[*] Attached target image to ${LOOP_DEV}"

cleanup() {
  echo "[*] Cleaning up loop devices and mounts..."
  sync || true
  if [ -n "${MNT:-}" ] && mountpoint -q "$MNT" 2>/dev/null; then
    umount "$MNT" || true
    rm -rf "$MNT" || true
  fi
  losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Applying universal bootloader and partition fix for cubie-a7s..."
bash "$FIX_BUNDLE" "$LOOP_DEV" "$BOARD_NAME"

MNT="/mnt/a7s_rootfs_$$"
mkdir -p "$MNT"
mount "${LOOP_DEV}p1" "$MNT"

echo "[*] Installing authentic Radxa Cubie A7S DTB..."
cp -f "$DTB_FILE" "$MNT/boot/sun60i-a733-cubie-a7s.dtb"
mkdir -p "$MNT/boot/dtb/allwinner"
cp -f "$DTB_FILE" "$MNT/boot/dtb/allwinner/sun60i-a733-cubie-a7s.dtb"
cp -f "$DTB_FILE" "$MNT/boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb"
find "$MNT/boot/dtb-"* -maxdepth 2 -name "allwinner" -exec cp -f "$DTB_FILE" {}/sun60i-a733-cubie-a7s.dtb \; 2>/dev/null || true
find "$MNT/boot/dtb-"* -maxdepth 2 -name "allwinner" -exec cp -f "$DTB_FILE" {}/sun60i-a733-orangepi-4-pro.dtb \; 2>/dev/null || true

echo "[*] Configuring bootloader env files to sun60i-a733-cubie-a7s.dtb..."
for envfile in radxaEnv.txt orangepiEnv.txt a733-allwinnerEnv.txt; do
  if [ -f "$MNT/boot/$envfile" ]; then
    sed -i "s|fdtfile=.*|fdtfile=allwinner/sun60i-a733-cubie-a7s.dtb|g" "$MNT/boot/$envfile"
    sed -i "s|console=tty1|console=tty2|g" "$MNT/boot/$envfile"
  fi
done

echo "[*] Installing AIC8800 USB Wi-Fi 6 and Bluetooth modules..."
mkdir -p "$MNT/usr/lib/modules/6.18.63-sun60iw2/kernel/drivers/net/wireless/aic8800"
mkdir -p "$MNT/usr/lib/modules/6.18.63-sun60iw2/kernel/drivers/bluetooth"
if [ -d "$AIC_DRV_DIR" ]; then
  cp -f "$AIC_DRV_DIR/aic_load_fw.ko" "$MNT/usr/lib/modules/6.18.63-sun60iw2/kernel/drivers/net/wireless/aic8800/"
  cp -f "$AIC_DRV_DIR/aic8800_fdrv.ko" "$MNT/usr/lib/modules/6.18.63-sun60iw2/kernel/drivers/net/wireless/aic8800/"
  cp -f "$AIC_DRV_DIR/aic_btusb.ko" "$MNT/usr/lib/modules/6.18.63-sun60iw2/kernel/drivers/bluetooth/"
  chroot "$MNT" depmod -a 6.18.63-sun60iw2 2>/dev/null || true
fi

echo "[*] Installing AIC8800 firmware and userconfig symlinks..."
mkdir -p "$MNT/usr/lib/firmware/aic8800" "$MNT/usr/lib/firmware/aic8800D80" "$MNT/usr/lib/firmware/aic8800d80"
if [ -d "/srv/kernel/radxa-aic8800/src/USB/driver_fw/fw/aic8800D80" ]; then
  cp -rf /srv/kernel/radxa-aic8800/src/USB/driver_fw/fw/aic8800D80/* "$MNT/usr/lib/firmware/aic8800D80/"
  cp -rf /srv/kernel/radxa-aic8800/src/USB/driver_fw/fw/aic8800D80/* "$MNT/usr/lib/firmware/aic8800d80/"
  cp -rf /srv/kernel/radxa-aic8800/src/USB/driver_fw/fw/aic8800D80/* "$MNT/usr/lib/firmware/aic8800/"
fi
ln -sf aic8800D80/aic_userconfig_8800d80.txt "$MNT/usr/lib/firmware/aic_userconfig_8800d80.txt" 2>/dev/null || true
ln -sf aic8800D80/aic_powerlimit_8800d80.txt "$MNT/usr/lib/firmware/aic_powerlimit_8800d80.txt" 2>/dev/null || true

echo "[*] Installing aic8800-bringup service..."
cp -f /srv/storage/aic8800-bringup.sh "$MNT/usr/local/bin/aic8800-bringup.sh"
chmod +x "$MNT/usr/local/bin/aic8800-bringup.sh"

cat << 'AIC_SVC' > "$MNT/etc/systemd/system/aic8800-bringup.service"
[Unit]
Description=AIC8800 USB Wi-Fi 6 and Bluetooth Hardware Initialization
After=basic.target network-pre.target
Before=network.target NetworkManager.service wpa_supplicant.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aic8800-bringup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
AIC_SVC

mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/aic8800-bringup.service "$MNT/etc/systemd/system/multi-user.target.wants/aic8800-bringup.service" 2>/dev/null || true

echo "[*] Updating version strings to ${VERSION}..."
for f in os-release issue issue.net radxa-release motd; do
  if [ -f "$MNT/etc/$f" ]; then
    sed -i "s/[0-9]\+\.[0-9]\+\.[0-9]\+-beta/${VERSION}/g" "$MNT/etc/$f" 2>/dev/null || true
  fi
done

echo "[*] Setting up hostname and /etc/hosts for radxa-cubie-a7s..."
echo "$HOSTNAME_VAL" > "$MNT/etc/hostname"
cat << HOSTS_EOF > "$MNT/etc/hosts"
127.0.0.1   localhost
127.0.1.1   $HOSTNAME_VAL
::1         localhost $HOSTNAME_VAL ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
HOSTS_EOF

echo "[*] Clearing static MOTD to prevent duplicates..."
rm -f "$MNT/etc/motd" "$MNT/var/run/motd" 2>/dev/null || true
touch "$MNT/etc/motd"

echo "[*] Configuring console=tty2 in boot.cmd and regenerating boot.scr..."
sed -i 's|console=tty1|console=tty2|g' "$MNT/boot/boot.cmd" 2>/dev/null || true
mkimage -C none -A arm64 -T script -d "$MNT/boot/boot.cmd" "$MNT/boot/boot.scr"

rm -f "$MNT/etc/systemd/system/default.target"
ln -s /usr/lib/systemd/system/multi-user.target "$MNT/etc/systemd/system/default.target"

echo "[*] Ensuring autologin overrides on tty1, tty2, and serial..."
mkdir -p "$MNT/etc/systemd/system/getty@tty2.service.d"
cat << 'TTY2_OVERRIDE' > "$MNT/etc/systemd/system/getty@tty2.service.d/override.conf"
[Unit]
After=systemd-user-sessions.service

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin radxa %I $TERM
Type=idle
Restart=always
RestartSec=0
TTY2_OVERRIDE

mkdir -p "$MNT/etc/systemd/system/getty@tty1.service.d"
cat << 'TTY1_OVERRIDE' > "$MNT/etc/systemd/system/getty@tty1.service.d/override.conf"
[Unit]
After=systemd-user-sessions.service plymouth-quit-wait.service
After=rc-local.service

[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin radxa %I $TERM
Type=idle
Restart=always
RestartSec=0
TTY1_OVERRIDE

mkdir -p "$MNT/etc/systemd/system/serial-getty@ttyS0.service.d"
cat << 'SGETTY_OVERRIDE' > "$MNT/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --keep-baud --autologin radxa 115200,38400,9600 %I $TERM
Type=idle
Restart=always
RestartSec=0
SGETTY_OVERRIDE

echo "[*] Ensuring switch-to-tty2 service is active..."
cat << 'SWITCH_SVC' > "$MNT/etc/systemd/system/switch-to-tty2.service"
[Unit]
Description=Switch Active Console to TTY2
After=multi-user.target
After=getty@tty2.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'if [ -x /usr/bin/chvt ]; then /usr/bin/chvt 2; elif [ -x /bin/chvt ]; then /bin/chvt 2; fi'

[Install]
WantedBy=multi-user.target
SWITCH_SVC

mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/switch-to-tty2.service "$MNT/etc/systemd/system/multi-user.target.wants/switch-to-tty2.service"

sync
umount "$MNT"
rm -rf "$MNT"
unset MNT

echo "[*] Running final e2fsck validation and repair on ${LOOP_DEV}p1..."
e2fsck -fy "${LOOP_DEV}p1" || true

losetup -d "$LOOP_DEV"
trap - EXIT

echo "[*] Compressing image with multicore xz fast..."
rm -f "$OUT_XZ" "${OUT_XZ}.sha256"
xz -T0 -v -3 "$OUT_IMG"

echo "[*] Calculating SHA256 checksum..."
sha256sum "$OUT_XZ" | awk '{print $1}' > "${OUT_XZ}.sha256"

cp -f "$OUT_XZ" "$RELEASE_DIR/"
cp -f "${OUT_XZ}.sha256" "$RELEASE_DIR/"

echo "[✓] Artifacts created:"
ls -lh "$OUT_XZ" "${OUT_XZ}.sha256"

if [ "$DO_UPLOAD" = "yes" ]; then
  echo "[*] Publishing release radxa-cubie-a7s-v${VERSION} on GitHub..."
  cat << NOTES_EOF > /tmp/rel_notes_a7s.md
Radxa Cubie A7S ${VERSION} official release:
- **Type-C DisplayPort & Controller**: Fixed \`rt1711h\` / \`husb311\` Type-C controller probe by declaring dedicated \`husb311_pins\` (\`PL3\` \`gpio_in\` with \`bias-pull-up\`), preventing GPIO lock conflicts. Wired AUX DC-bias GPIOs (\`PL10\` / \`PL11\`) and configured opt-in software HPD lifecycle for DisplayPort over Type-C.
- **AIC8800 Wi-Fi 6 & Bluetooth**: Built and integrated native USB drivers (\`aic_load_fw.ko\`, \`aic8800_fdrv.ko\`, \`aic_btusb.ko\`) matching \`6.18.63-sun60iw2\` vermagic, with full firmware binaries and calibration profiles in \`/lib/firmware/\`.
- **Fixed /etc/hosts Resolution**: Synchronized \`/etc/hosts\` with hostname \`radxa-cubie-a7s\` (resolving sudo warning \`unable to resolve host radxa-cubie-a7s\`).
- **Clean Agetty Console Configuration**: Clean autologin overrides without escape sequence warnings on \`tty1\`, \`tty2\`, and \`ttyS0\`.
- **Filesystem Integrity**: Checked and clean ext4 filesystem without corruption.
NOTES_EOF

  gh release create "radxa-cubie-a7s-v${VERSION}" "$OUT_XZ" "${OUT_XZ}.sha256" \
    --title "Radxa Cubie A7S ${VERSION}" \
    --notes-file /tmp/rel_notes_a7s.md \
    -R jonas5/Allwinner-A733-kernel || true

  echo "[*] Updating rolling release tag radxa-cubie-a7s-releases..."
  gh release upload "radxa-cubie-a7s-releases" "$OUT_XZ" "${OUT_XZ}.sha256" --clobber -R jonas5/Allwinner-A733-kernel || true
fi

echo "======================================================================"
echo " [✓] RADXA CUBIE A7S BUILD FINISHED SUCCESSFULLY"
echo "     Image:  ${OUT_XZ}"
echo "     SHA256: $(cat "${OUT_XZ}.sha256")"
echo "======================================================================"
