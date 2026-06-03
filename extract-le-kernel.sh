#!/bin/bash
# extract-le-kernel.sh — Extract kernel, DTBs, overlays, and modules from LibreELEC image
# Usage: ./extract-le-kernel.sh <image.gz> <output_dir>

set -euo pipefail

IMAGE_GZ="${1:?Usage: $0 <image.gz> <output_dir>}"
OUTDIR="${2:?Usage: $0 <image.gz> <output_dir>}"

mkdir -p "$OUTDIR"

echo "=== Decompressing image ==="
IMAGE_RAW="${IMAGE_GZ%.gz}"
if [ ! -f "$IMAGE_RAW" ]; then
    gunzip -k "$IMAGE_GZ"
fi

echo "=== Mounting partitions ==="
BOOT_OFFSET=$((8192 * 512))   # FAT32 boot partition starts at sector 8192
ROOT_OFFSET=$((534528 * 512)) # ext4 root partition starts at sector 534528

MNT_BOOT=$(mktemp -d)
MNT_ROOT=$(mktemp -d)

sudo mount -o loop,offset=$BOOT_OFFSET "$IMAGE_RAW" "$MNT_BOOT"
sudo mount -o loop,offset=$ROOT_OFFSET "$IMAGE_RAW" "$MNT_ROOT"

echo "=== Extracting kernel + DTBs + overlays ==="
cp "$MNT_BOOT/kernel.img" "$OUTDIR/"
cp "$MNT_BOOT"/*.dtb "$OUTDIR/"
cp -r "$MNT_BOOT/overlays" "$OUTDIR/"

echo "=== Extracting kernel modules ==="
MODULES_DIR=$(ls -d "$MNT_ROOT/lib/modules/"*/ 2>/dev/null | head -1)
if [ -n "$MODULES_DIR" ]; then
    KVER=$(basename "$MODULES_DIR")
    echo "Kernel version: $KVER"
    tar -czf "$OUTDIR/modules-${KVER}.tar.gz" -C "$MNT_ROOT/lib/modules" "$KVER"
else
    echo "WARNING: No modules found in $MNT_ROOT/lib/modules/"
fi

echo "=== Extracting SYSTEM ==="
cp "$MNT_BOOT/SYSTEM" "$OUTDIR/" 2>/dev/null || echo "No SYSTEM file"

echo "=== Checksums ==="
cd "$OUTDIR"
md5sum kernel.img > kernel.img.md5
md5sum SYSTEM > SYSTEM.md5 2>/dev/null || true

cd - > /dev/null

echo "=== Unmounting ==="
sudo umount "$MNT_BOOT"
sudo umount "$MNT_ROOT"
rmdir "$MNT_BOOT" "$MNT_ROOT"

echo "=== Done ==="
echo "Output in: $OUTDIR"
ls -la "$OUTDIR/"
