#!/bin/bash
# Deploy LE12 Mesa full swap for Widevine secure video on crackberry5
# Run on crackberry5 (LibreELEC) as root

set -e

echo "=== LE12 Mesa Full Swap Deploy ==="

# Stop Kodi first
echo "Stopping Kodi..."
systemctl stop kodi 2>/dev/null || true
sleep 2
killall kodi.bin 2>/dev/null || true
sleep 1

# Remove existing bind-mounts
for mp in /usr/lib/gbm/dri_gbm.so /usr/lib/libgbm.so.1.0.0 \
          /usr/lib/libEGL.so.1.0.0 /usr/lib/libGLESv2.so.2.0.0; do
    umount "$mp" 2>/dev/null || true
done

# Verify LE12 libs exist
REQUIRED="/storage/dri_gbm_le12_orig.so /storage/libgbm_le12_orig.so \
          /storage/libEGL_le12.so /storage/libGLESv2_le12.so \
          /storage/libgallium-25.1.9.so"

for f in $REQUIRED; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing $f — extract from LE12 SYSTEM first"
        exit 1
    fi
done

echo "All LE12 libs present. Sizes:"
ls -la $REQUIRED

# Apply bind-mounts
echo "Applying bind-mounts..."
mount --bind /storage/dri_gbm_le12_orig.so /usr/lib/gbm/dri_gbm.so
mount --bind /storage/libgbm_le12_orig.so /usr/lib/libgbm.so.1.0.0
mount --bind /storage/libEGL_le12.so /usr/lib/libEGL.so.1.0.0
mount --bind /storage/libGLESv2_le12.so /usr/lib/libGLESv2.so.2.0.0

# Fake addon for libgallium LD_LIBRARY_PATH injection
echo "Setting up libgallium injection..."
mkdir -p /storage/.kodi/addons/mesa-le12/lib
ln -sf /storage/libgallium-25.1.9.so /storage/.kodi/addons/mesa-le12/lib/libgallium-25.1.9.so

# Verify
echo "Verifying bind-mounts..."
mount | grep -E "dri_gbm|libgbm|libEGL|libGLES" | wc -l
echo "bind-mounts active (expected: 4)"

# Update autostart.sh for persistence
AUTOSTART=/storage/.config/autostart.sh
if ! grep -q "mesa-le12" "$AUTOSTART" 2>/dev/null; then
    echo "Adding Mesa swap to autostart.sh..."
    # Keep existing entries, add Mesa swap at the end
    cat >> "$AUTOSTART" << 'EOF'

# === LE12 Mesa full swap for Widevine ===
mkdir -p /storage/.kodi/addons/mesa-le12/lib
ln -sf /storage/libgallium-25.1.9.so /storage/.kodi/addons/mesa-le12/lib/libgallium-25.1.9.so
mount --bind /storage/dri_gbm_le12_orig.so /usr/lib/gbm/dri_gbm.so
mount --bind /storage/libgbm_le12_orig.so /usr/lib/libgbm.so.1.0.0
mount --bind /storage/libEGL_le12.so /usr/lib/libEGL.so.1.0.0
mount --bind /storage/libGLESv2_le12.so /usr/lib/libGLESv2.so.2.0.0
EOF
    chmod +x "$AUTOSTART"
    echo "autostart.sh updated"
fi

# Start Kodi
echo "Starting Kodi..."
systemctl start kodi
sleep 6

if systemctl is-active kodi >/dev/null && pidof kodi.bin >/dev/null; then
    echo "✅ Kodi running with LE12 Mesa full swap"
    echo "Verify with: cat /proc/\$(pidof kodi.bin)/maps | grep libgallium-25.1.9"
else
    echo "❌ Kodi failed to start. Check: journalctl -u kodi --no-pager -n 10"
    exit 1
fi
