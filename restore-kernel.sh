#!/bin/bash
# restore-kernel.sh — Restore backed-up kernel files to /flash
# Run ON the Raspberry Pi you're restoring (mount -o remount,rw /flash first)

set -euo pipefail

BACKUP_DIR="${1:?Usage: $0 <backup_dir>}"

if [ ! -f "$BACKUP_DIR/kernel.img" ]; then
    echo "ERROR: $BACKUP_DIR/kernel.img not found"
    exit 1
fi

echo "=== Remounting /flash read-write ==="
mount -o remount,rw /flash

echo "=== Restoring from $BACKUP_DIR ==="

cp "$BACKUP_DIR/kernel.img" /flash/
cp "$BACKUP_DIR"/*.dtb /flash/ 2>/dev/null || true
if [ -d "$BACKUP_DIR/overlays" ]; then
    rm -rf /flash/overlays
    cp -r "$BACKUP_DIR/overlays" /flash/
fi

# Only restore cmdline.txt if explicitly wanted
if [ "${2:-}" = "--with-cmdline" ] && [ -f "$BACKUP_DIR/cmdline.txt" ]; then
    cp "$BACKUP_DIR/cmdline.txt" /flash/
    echo "cmdline.txt restored (--with-cmdline flag)"
else
    echo "cmdline.txt NOT restored (use --with-cmdline to include)"
fi

[ -f "$BACKUP_DIR/SYSTEM" ] && cp "$BACKUP_DIR/SYSTEM" /flash/ 2>/dev/null || true

echo "=== Done ==="
echo "Restored kernel: $(cat /flash/kernel.img.md5 2>/dev/null || md5sum /flash/kernel.img)"
echo ""
echo "REBOOT REQUIRED: reboot"
