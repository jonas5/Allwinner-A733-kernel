#!/usr/bin/env python3
"""
Hardware Framebuffer Bootsplash Spinner for Allwinner A733
- Renders /boot/boot.bmp (or /boot/logo.bmp) centered on /dev/fb0
- Animates a smooth rotating waiting wheel below the logo
- Listens to /dev/input/event* for ESC / Enter / Space to exit immediately
- Exits cleanly when systemd finishes booting and getty takes over
"""

import os, sys, time, math, glob, select, signal, struct, fcntl, ctypes

BOOT_BMP = '/boot/boot.bmp'
LOGO_BMP = '/boot/logo.bmp'
FB_DEVICE = '/dev/fb0'

class fb_fix_screeninfo(ctypes.Structure):
    _fields_ = [
        ('id', ctypes.c_char * 16),
        ('smem_start', ctypes.c_ulong),
        ('smem_len', ctypes.c_uint32),
        ('type', ctypes.c_uint32),
        ('type_aux', ctypes.c_uint32),
        ('visual', ctypes.c_uint32),
        ('xpanstep', ctypes.c_uint16),
        ('ypanstep', ctypes.c_uint16),
        ('ywrapstep', ctypes.c_uint16),
        ('line_length', ctypes.c_uint32),
        ('mmio_start', ctypes.c_ulong),
        ('mmio_len', ctypes.c_uint32),
        ('accel', ctypes.c_uint32),
        ('capabilities', ctypes.c_uint16),
        ('reserved', ctypes.c_uint16 * 2),
    ]

def get_fb_info():
    try:
        with open(FB_DEVICE, 'rb') as f:
            vbuf = bytearray(160)
            fcntl.ioctl(f.fileno(), 0x4600, vbuf)
            xres, yres, vxres, vyres, xoff, yoff, bpp = struct.unpack('<7I', vbuf[:28])

            line_length = 0
            try:
                fix = fb_fix_screeninfo()
                fcntl.ioctl(f.fileno(), 0x4602, fix)
                line_length = fix.line_length
            except Exception:
                pass

            if line_length == 0:
                try:
                    with open('/sys/class/graphics/fb0/line_length', 'r') as sf:
                        line_length = int(sf.read().strip())
                except Exception:
                    line_length = xres * (bpp // 8)

            return xres, yres, bpp, line_length
    except Exception:
        return None

def load_bmp(bmp_path):
    if not os.path.isfile(bmp_path):
        return None
    with open(bmp_path, 'rb') as f:
        data = f.read()
    if len(data) < 54 or data[:2] != b'BM':
        return None
    offset = struct.unpack('<I', data[10:14])[0]
    w, h, planes, bpp = struct.unpack('<iiHH', data[18:30])
    h_abs = abs(h)
    if bpp not in (24, 32):
        return None
    row_stride = (w * (bpp // 8) + 3) & (~3)
    pixels = []
    raw_pixels = data[offset:]
    for y in range(h_abs):
        actual_y = (h_abs - 1 - y) if h > 0 else y
        row_start = actual_y * row_stride
        row = raw_pixels[row_start : row_start + w * (bpp // 8)]
        pixels.append(row)
    return w, h_abs, bpp, pixels

running = True
def sig_handler(signum, frame):
    global running
    running = False

def hide_cursor_and_cls():
    for tty in ['/dev/tty1', '/dev/tty0']:
        if os.path.exists(tty):
            try:
                with open(tty, 'wb', buffering=0) as f:
                    f.write(b'\033[?25l\033[2J\033[H')
            except Exception:
                pass

def show_cursor_and_cls():
    for tty in ['/dev/tty1', '/dev/tty0']:
        if os.path.exists(tty):
            try:
                with open(tty, 'wb', buffering=0) as f:
                    f.write(b'\033[2J\033[H\033[?25h')
            except Exception:
                pass

def open_keyboard_devices():
    fds = []
    for ev in glob.glob('/dev/input/event*'):
        try:
            fd = os.open(ev, os.O_RDONLY | os.O_NONBLOCK)
            fds.append(fd)
        except Exception:
            pass
    return fds

def main():
    signal.signal(signal.SIGTERM, sig_handler)
    signal.signal(signal.SIGINT, sig_handler)

    hide_cursor_and_cls()

    # Wait for /dev/fb0 to become available
    fb_info = None
    for _ in range(60):
        if os.path.exists(FB_DEVICE):
            fb_info = get_fb_info()
            if fb_info and fb_info[0] > 0 and fb_info[1] > 0:
                break
        time.sleep(0.05)

    if not fb_info:
        sys.exit(0)

    fb_w, fb_h, fb_bpp, fb_stride = fb_info
    bytes_per_pixel = fb_bpp // 8

    bmp_data = load_bmp(BOOT_BMP) or load_bmp(LOGO_BMP)
    if not bmp_data:
        sys.exit(0)

    bmp_w, bmp_h, bmp_bpp, bmp_rows = bmp_data

    start_x = max(0, (fb_w - bmp_w) // 2)
    start_x = (start_x // 16) * 16
    start_y = max(0, (fb_h - bmp_h) // 2 - 45)

    try:
        fb_fd = open(FB_DEVICE, 'r+b', buffering=0)
    except Exception:
        sys.exit(0)

    # Clear screen to black
    try:
        fb_fd.seek(0)
        fb_fd.write(bytes([0]) * (fb_h * fb_stride))
    except Exception:
        pass

    # Draw centered logo
    for y in range(min(bmp_h, fb_h - start_y)):
        dest_offset = (start_y + y) * fb_stride + start_x * bytes_per_pixel
        fb_fd.seek(dest_offset)
        row_src = bmp_rows[y]
        
        if fb_bpp == 32 and bmp_bpp == 24:
            row_32 = bytearray(min(bmp_w, fb_w - start_x) * 4)
            for x in range(min(bmp_w, fb_w - start_x)):
                b = row_src[x*3]
                g = row_src[x*3 + 1]
                r = row_src[x*3 + 2]
                row_32[x*4] = b
                row_32[x*4 + 1] = g
                row_32[x*4 + 2] = r
                row_32[x*4 + 3] = 0xff
            fb_fd.write(row_32)
        elif fb_bpp == bmp_bpp:
            fb_fd.write(row_src[:(fb_w - start_x) * bytes_per_pixel])

    # Spinner geometry (placed below the logo)
    spin_cx = fb_w // 2
    spin_cy = start_y + bmp_h + 45
    radius = 24
    dot_count = 12
    dot_r = 4

    input_fds = open_keyboard_devices()
    frame = 0

    try:
        while running:
            # Check keyboard breaks (ESC / Enter / Space)
            if input_fds:
                rlist, _, _ = select.select(input_fds, [], [], 0.0)
                if rlist:
                    for rfd in rlist:
                        try:
                            ev = os.read(rfd, 24)
                            if len(ev) >= 24:
                                tv_sec, tv_usec, ev_type, ev_code, ev_val = struct.unpack('qqHHi', ev[:24])
                                if ev_val > 0 and ev_code in (1, 28, 57):
                                    running = False
                                    break
                        except Exception:
                            pass
                    if not running:
                        break

            # Draw spinner frame
            for i in range(dot_count):
                angle = (2 * math.pi / dot_count) * i - (frame * 0.28)
                cx = int(spin_cx + radius * math.cos(angle))
                cy = int(spin_cy + radius * math.sin(angle))
                alpha = (i + 1) / float(dot_count)
                intensity = int(50 + 205 * alpha)
                color = bytes([intensity, intensity, intensity, 0xff]) if fb_bpp == 32 else bytes([intensity, intensity, intensity])

                for dy in range(-dot_r, dot_r + 1):
                    py = cy + dy
                    if py < 0 or py >= fb_h:
                        continue
                    dx_limit = int(math.sqrt(max(0, dot_r * dot_r - dy * dy)))
                    left_x = max(0, cx - dx_limit)
                    right_x = min(fb_w - 1, cx + dx_limit)
                    span_len = right_x - left_x + 1
                    if span_len > 0:
                        fb_fd.seek(py * fb_stride + left_x * bytes_per_pixel)
                        fb_fd.write(color * span_len)

            time.sleep(0.04)
            frame = (frame + 1) % dot_count

            # Clear spinner track
            clear_box = (dot_r + radius + 8)
            box_start_y = max(0, spin_cy - clear_box)
            box_end_y = min(fb_h, spin_cy + clear_box)
            box_start_x = max(0, spin_cx - clear_box)
            box_end_x = min(fb_w, spin_cx + clear_box)
            span = (box_end_x - box_start_x) * bytes_per_pixel
            clear_bytes = bytes([0]) * span
            for py in range(box_start_y, box_end_y):
                fb_fd.seek(py * fb_stride + box_start_x * bytes_per_pixel)
                fb_fd.write(clear_bytes)

    finally:
        for fd in input_fds:
            try:
                os.close(fd)
            except Exception:
                pass
        try:
            fb_fd.seek(0)
            fb_fd.write(bytes([0]) * (fb_h * fb_stride))
            fb_fd.close()
        except Exception:
            pass
        show_cursor_and_cls()

if __name__ == '__main__':
    main()
