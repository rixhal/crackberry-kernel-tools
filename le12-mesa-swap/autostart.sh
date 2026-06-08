#!/bin/sh

# WiFi: ensure not soft-blocked at boot (CYW43455 shares antenna with BLE)
rfkill unblock wlan

# === LE12 Mesa full swap for Widevine secure video ===
# Fix for LE13 nightly-20260607 Mesa 26.1.2 ABI break
# Injects libgallium-25.1.9.so via fake addon dir (99-kodi.conf auto-adds to LD_LIBRARY_PATH)
mkdir -p /storage/.kodi/addons/mesa-le12/lib
ln -sf /storage/libgallium-25.1.9.so /storage/.kodi/addons/mesa-le12/lib/libgallium-25.1.9.so

mount --bind /storage/dri_gbm_le12_orig.so /usr/lib/gbm/dri_gbm.so
mount --bind /storage/libgbm_le12_orig.so /usr/lib/libgbm.so.1.0.0
mount --bind /storage/libEGL_le12.so /usr/lib/libEGL.so.1.0.0
mount --bind /storage/libGLESv2_le12.so /usr/lib/libGLESv2.so.2.0.0

# === LE12 Kernel Module Overlay ===
if [ -d /storage/le12-modules/6.12.87+rpt-rpi-2712 ]; then
  mkdir -p /lib/modules
  mount --bind /storage/le12-modules/6.12.87+rpt-rpi-2712 /lib/modules/6.12.87+rpt-rpi-2712 2>/dev/null
fi

# Tailscale autostart
TAILSCALE_BIN=/storage/tailscale
TAILSCALED_BIN=/storage/tailscaled
STATE_DIR=/storage/.config/tailscale
mkdir -p $STATE_DIR/logs
if ! pgrep -f tailscaled > /dev/null 2>&1; then
  $TAILSCALED_BIN \
    --state=$STATE_DIR/tailscaled.state \
    --socket=$STATE_DIR/tailscaled.sock \
    --port=41641 \
    > $STATE_DIR/logs/tailscaled.log 2>&1 &
  for i in $(seq 1 10); do
    [ -S $STATE_DIR/tailscaled.sock ] && break
    sleep 1
  done
fi

# Load Switch 2 controller kernel driver
if [ -f /storage/.config/modules/hid-switch2.ko ]; then
  insmod /storage/.config/modules/hid-switch2.ko 2>/dev/null
  insmod /storage/.config/modules/switch2-usb.ko 2>/dev/null
fi
modprobe switch2-bt-ff 2>/dev/null || true
