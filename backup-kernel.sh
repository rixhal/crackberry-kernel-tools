#!/bin/bash
# backup-kernel.sh — Backup current kernel from running LibreELEC to SSD/storage
# Run ON the Raspberry Pi you're backing up

set -euo pipefail

BACKUP_DIR="${1:-/storage/kernel-backup-$(date +%Y%m%d-%H%M%S)}"

echo "=== Backing up kernel to $BACKUP_DIR ==="
mkdir -p "$BACKUP_DIR"

# Backup /flash contents (kernel, DTBs, overlays, config)
echo "Copying /flash..."
cp /flash/kernel.img "$BACKUP_DIR/"
cp /flash/*.dtb "$BACKUP_DIR/"
cp -r /flash/overlays "$BACKUP_DIR/"
cp /flash/cmdline.txt "$BACKUP_DIR/" 2>/dev/null || echo "No cmdline.txt"
cp /flash/config.txt "$BACKUP_DIR/" 2>/dev/null || echo "No config.txt"
cp /flash/SYSTEM "$BACKUP_DIR/" 2>/dev/null || echo "No SYSTEM file"
cp /flash/SYSTEM.md5 "$BACKUP_DIR/" 2>/dev/null || true

# Backup kernel modules
echo "Copying kernel modules..."
KVER=$(uname -r)
tar -czf "$BACKUP_DIR/modules-${KVER}.tar.gz" -C /lib/modules "$KVER" 2>/dev/null || echo "WARNING: Module backup failed"

echo "=== Checksums ==="
cd "$BACKUP_DIR"
md5sum kernel.img > kernel.img.md5
md5sum SYSTEM > SYSTEM.md5 2>/dev/null || true
cd - > /dev/null

echo "=== Done ==="
echo "Backup saved to: $BACKUP_DIR"
ls -la "$BACKUP_DIR/"
