# Allwinner A733 SD Card & Bootloader Remediation Guide

This guide details the technical root causes and exact procedures for resolving boot, display (`tty1` / HDMI / USB-C DP Alt-mode), serial console (`ttyS0`), and root filesystem mounting issues across Allwinner A733 platforms (**Orange Pi 4 Pro**, **Radxa Cubie A7A**, and **Radxa Cubie A7S**).

---

## 1. Technical Root Causes

### A. Root Partition Lookup Failure (`ALERT! /dev/disk/by-uuid/... does not exist`)
- **Symptom**: During boot on Debian/Ubuntu, the kernel loads initramfs but drops into an emergency BusyBox shell with:
  ```
  ALERT! /dev/disk/by-uuid/9e89c25a-38da-4e90-9c5e-ae2d1aca30a4 does not exist. Dropping to a shell!
  ```
- **Root Cause**: The image build harness (`orangepi-build`) embeds the loopback partition UUID created on the build runner VM into `/boot/orangepiEnv.txt`. When booted on physical board hardware, MMC storage driver enumeration takes 1.0–1.5 seconds. Debian initramfs fails UUID resolution before the MMC block device is fully scanned.
- **Remedy**: Specify explicit device fallback `rootdev=/dev/mmcblk0p1` along with `rootwait rootdelay=1` in the boot environment.

### B. Display Terminal Disabled (`tty1` Quiet / Black Screen on HDMI)
- **Symptom**: Board boots, UART0 serial prints output, but HDMI / DP display stops after early boot or stays blank without an interactive login prompt.
- **Root Cause**: In Linux kernel argument parsing, when multiple `console=` options are passed (e.g. `console=tty1 console=ttyS0,115200`), the **last** console parameter receives `/dev/console` ownership and primary systemd interactive focus. When `console=ttyS0` is placed last, systemd directs interactive output exclusively to serial, leaving `tty1` dormant.
- **Remedy**:
  1. Set console arguments to `console=ttyS0,115200 console=tty1` so HDMI (`tty1`) is the active primary interactive display console while serial UART (`ttyS0`) continues to receive full kernel logs.
  2. Install dedicated systemd autologin overrides for both `serial-getty@ttyS0` and `getty@tty1` under `/etc/systemd/system/`.

### C. Radxa Cubie A7S USB-C DisplayPort Alt-Mode (HDMI Adapter)
- **Symptom**: No display on external HDMI monitors connected via Type-C to HDMI adapter dongles.
- **Root Cause**: In `sun60i-a733-cubie-a7s.dts`, node `&edp0` had `edp_lane_cnt = <4>;` and lacked explicit `force_mode = "dp";`. Standard USB-C to HDMI / DP adapter cables use 2-lane DP Alt-Mode to reserve the remaining high-speed lanes for USB 3.0 / PD signals. The Cadence combo-phy failed link training on 4-lane negotiation.
- **Remedy**: Configure `edp_lane_cnt = <2>;` and `force_mode = "dp";` in `&edp0`.

### D. Missing Sector 16 Universal Bootloader
- **Symptom**: Complete lack of boot (no UART output, no U-Boot prompt) on certain raw images.
- **Root Cause**: Allwinner A733 BROM reads initial bootloader headers strictly at Sector 16 (offset 8192 bytes / `seek=16` at 512-byte blocks).
- **Remedy**: Flash verified universal bootloader binary (`bootloader-orangepi-4-pro.bin`) directly to sector 16 of the raw SD card block device.

---

## 2. SD Card Remediation Tool (`fix-a7a-sdcard.sh`)

A self-contained universal repair script has been published to automatically patch any A733 SD card on a Linux workstation.

### Tool Download
From GitHub Releases:
```bash
wget https://github.com/jonas5/Allwinner-A733-kernel/releases/download/orangepi-4-pro-releases/fix-a7a-sdcard.sh
chmod +x fix-a7a-sdcard.sh
```

### Usage Instructions

#### Option A: Repair Raw SD Card Device (Recommended)
Insert SD card into PC (e.g., `/dev/sdb` or `/dev/mmcblk0`):
```bash
# Auto-detects board or specify explicitly: opi4pro | cubie-a7a | cubie-a7s
sudo ./fix-a7a-sdcard.sh /dev/sdb cubie-a7a
```

#### Option B: Repair Mounted Root Partition
If the SD card partition is already mounted:
```bash
sudo ./fix-a7a-sdcard.sh /media/$USER/rootfs opi4pro
```

---

## 3. Manual Step-by-Step Fix

If repairing manually without the script:

1. **Write Sector 16 Bootloader**:
   ```bash
   dd if=bootloader-orangepi-4-pro.bin of=/dev/sdX bs=512 seek=16 conv=notrunc
   ```

2. **Mount Root Partition**:
   ```bash
   mkdir -p /mnt/sdcard
   mount /dev/sdX1 /mnt/sdcard
   ```

3. **Update `/boot/orangepiEnv.txt` (or `radxaEnv.txt`)**:
   ```ini
   verbosity=7
   bootlogo=false
   console=both
   earlycon=on
   overlay_prefix=sun60i-a733
   fdtfile=allwinner/sun60i-a733-orangepi-4-pro.dtb
   rootdev=/dev/mmcblk0p1
   rootfstype=ext4
   extraargs=cma=256M
   ```
   *(For Radxa Cubie A7A, use `fdtfile=allwinner/sun60i-a733-cubie-a7a.dtb`)*
   *(For Radxa Cubie A7S, use `fdtfile=allwinner/sun60i-a733-cubie-a7s.dtb`)*

4. **Ensure `boot.cmd` puts `tty1` last**:
   ```bash
   # In boot.cmd:
   if test "${console}" = "both"; then setenv consoleargs "console=ttyS0,115200 console=tty1"; fi
   
   # Recompile boot.scr:
   mkimage -C none -A arm -T script -d /mnt/sdcard/boot/boot.cmd /mnt/sdcard/boot/boot.scr
   ```

5. **Enable Interactive Display & Serial Autologin**:
   ```bash
   # Serial UART autologin
   mkdir -p /mnt/sdcard/etc/systemd/system/serial-getty@ttyS0.service.d
   cat << 'EOF' > /mnt/sdcard/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
   [Service]
   ExecStart=
   ExecStart=-/sbin/agetty -o "-p -- \u" --autologin root --noclear -s %I 115200 vt220
   StandardInput=tty
   StandardOutput=tty
   EOF

   # HDMI display autologin
   mkdir -p /mnt/sdcard/etc/systemd/system/getty@tty1.service.d
   cat << 'EOF' > /mnt/sdcard/etc/systemd/system/getty@tty1.service.d/override.conf
   [Service]
   ExecStart=
   ExecStart=-/sbin/agetty -o "-p -- \u" --autologin root --noclear %I 38400 linux
   StandardInput=tty
   StandardOutput=tty
   EOF
   ```

6. **Unmount and Eject**:
   ```bash
   sync
   umount /mnt/sdcard
   ```

---

## 4. Framebuffer Bootsplash with Animated Spinner

A hardware-agnostic spinning wheel animation has been integrated into the boot sequence:
- **Location**: `/usr/local/bin/a733-bootsplash-spinner`
- **Systemd Unit**: `/etc/systemd/system/a733-bootsplash-spinner.service` (enabled in `sysinit.target`)
- **Behavior**:
  1. Detects framebuffer `/dev/fb0` geometry and dynamically parses `/boot/boot.bmp` (works with Orange Pi, Radxa, or custom 24bpp/32bpp BMPs).
  2. Centers the logo on the display and renders a smooth 12-dot spinning wheel indicator directly below it.
  3. Ordered `Before=getty.target systemd-user-sessions.service`, smoothly terminating and clearing the display the moment the login prompt is ready.
