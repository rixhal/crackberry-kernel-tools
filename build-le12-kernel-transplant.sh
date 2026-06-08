#!/bin/bash
# build-le12-kernel-transplant.sh
# Build a hybrid LE12 kernel + LE13 userspace for RPi5
# LE12 kernel = stable V3D | LE13 SYSTEM = latest Kodi addons
#
# Usage: ./build-le12-kernel-transplant.sh [--deploy]
#   Without --deploy: build only, show diff from last version
#   With --deploy: push to crackberry5 and reboot

set -euo pipefail

DEPLOY_HOST="${DEPLOY_HOST:-10.10.10.140}"
DEPLOY_USER="${DEPLOY_USER:-root}"
WORKDIR="${WORKDIR:-/tmp/le-transplant}"
LE13_BASE="https://test.libreelec.tv/13.0/RPi/RPi5"
LE12_URL="https://releases.libreelec.tv/LibreELEC-RPi5.aarch64-12.2.1.img.gz"
MARKER_FILE="/storage/.le-transplant-version"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

cleanup() {
    log "Cleaning up..."
    sudo umount /mnt/le12-boot 2>/dev/null || true
    sudo umount /mnt/le12-system 2>/dev/null || true
    sudo umount /mnt/le13-boot 2>/dev/null || true
    sudo umount /mnt/le13-system 2>/dev/null || true
    for img in "$WORKDIR/le12.img" "$WORKDIR/le13.img"; do
        LOOP=$(sudo losetup -j "$img" 2>/dev/null | grep -oP '/dev/loop\d+' | head -1)
        [ -n "$LOOP" ] && sudo losetup -d "$LOOP" 2>/dev/null || true
    done
    sudo rm -rf "$WORKDIR"
}
trap cleanup EXIT

# ── 1. Find latest Nightly ──────────────────────────────────
log "Searching for latest LE13 Nightly..."
LATEST=$(curl -sL "$LE13_BASE/" | grep -oP 'LibreELEC-RPi5.*?nightly-\d{8}-[a-f0-9]+\.img\.gz' | sort | tail -1)
if [ -z "$LATEST" ]; then
    err "No Nightly found!"
    exit 1
fi
LATEST_DATE=$(echo "$LATEST" | grep -oP '\d{8}')
LATEST_COMMIT=$(echo "$LATEST" | grep -oP '[a-f0-9]{7}(?=\.img)')
log "Latest Nightly: $LATEST_DATE ($LATEST_COMMIT)"

# ── 2. Check if update needed ─────────────────────────────────
CURRENT=$(ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_HOST" "cat $MARKER_FILE 2>/dev/null" 2>/dev/null || echo "none")
if [ "$CURRENT" = "$LATEST_DATE-$LATEST_COMMIT" ]; then
    log "Already up to date ($CURRENT). Nothing to do."
    exit 0
fi
log "Update available: $CURRENT → $LATEST_DATE-$LATEST_COMMIT"

# ── 3. Download images ───────────────────────────────────────
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log "Downloading LE12.2.1 Stable..."
if [ ! -f le12.img ]; then
    curl -sL "$LE12_URL" -o le12.img.gz
    gunzip -f le12.img.gz
fi

LE13_URL="$LE13_BASE/$LATEST"
log "Downloading LE13 Nightly..."
curl -sL "$LE13_URL" -o le13.img.gz
gunzip -f le13.img.gz

# ── 4. Extract LE12 kernel + modules ────────────────────────
log "Extracting LE12 kernel + modules..."
sudo losetup -fP le12.img
LE12_LOOP=$(sudo losetup -j le12.img | grep -oP '/dev/loop\d+(?=:)' | head -1)
[ -z "$LE12_LOOP" ] && { err "losetup LE12 failed"; exit 1; }
sudo mkdir -p /mnt/le12-boot /mnt/le12-system
sudo mount ${LE12_LOOP}p1 /mnt/le12-boot || { err "Mount LE12 boot failed"; exit 1; }
sudo mount -o loop /mnt/le12-boot/SYSTEM /mnt/le12-system || { err "Mount LE12 SYSTEM failed"; exit 1; }

# LibreELEC stores kernel modules in overlays: not in /lib/modules,
# but in /usr/lib/kernel-overlays/base/lib/modules/
OVERLAY_BASE="/mnt/le12-system/usr/lib/kernel-overlays/base/lib/modules"
[ -d "$OVERLAY_BASE" ] || { err "No kernel-overlays in LE12 SYSTEM — wrong image?"; exit 1; }

LE12_KERNEL_VER=$(sudo ls "$OVERLAY_BASE" | head -1)
[ -z "$LE12_KERNEL_VER" ] && { err "No kernel version found in LE12 Overlay"; exit 1; }
log "LE12 kernel version: $LE12_KERNEL_VER"

KO_COUNT=$(sudo find "$OVERLAY_BASE/$LE12_KERNEL_VER" -name "*.ko" | wc -l)
[ "$KO_COUNT" -lt 10 ] && { err "Only $KO_COUNT .ko files in Overlay"; exit 1; }
log "$KO_COUNT kernel modules found"

# Copy kernel + DTBs
sudo cp /mnt/le12-boot/kernel.img "$WORKDIR/"
sudo cp /mnt/le12-boot/*.dtb "$WORKDIR/"
sudo cp -r /mnt/le12-boot/overlays "$WORKDIR/" 2>/dev/null || true

# Save modules from overlay path
sudo tar czf "$WORKDIR/le12-modules.tar.gz" -C "$OVERLAY_BASE" "$LE12_KERNEL_VER"

# ── 5. Mount LE13 SYSTEM + patch ───────────────────────────
log "Extracting LE13 SYSTEM..."
sudo losetup -fP le13.img
LE13_LOOP=$(sudo losetup -j le13.img | grep -oP '/dev/loop\d+(?=:)' | head -1)
sudo mkdir -p /mnt/le13-boot /mnt/le13-system
sudo mount ${LE13_LOOP}p1 /mnt/le13-boot

LE13_KERNEL_VER=$(sudo unsquashfs -l /mnt/le13-boot/SYSTEM 2>/dev/null | grep 'lib/modules/' | head -1 | awk -F/ '{print $4}' || echo "unknown")

log "Patching LE13 SYSTEM (LE12 modules into overlay)..."
sudo unsquashfs -d "$WORKDIR/squashfs-root" /mnt/le13-boot/SYSTEM

# Remove LE13 overlay modules, copy LE12 overlay modules in
LE13_OVERLAY="$WORKDIR/squashfs-root/usr/lib/kernel-overlays/base/lib/modules"
sudo bash -c "rm -rf $LE13_OVERLAY/*"
sudo mkdir -p "$LE13_OVERLAY"
sudo tar xzf "$WORKDIR/le12-modules.tar.gz" -C "$LE13_OVERLAY/"

# Set version marker
echo "LE12-Kernel: $LE12_KERNEL_VER | LE13-Nightly: $LATEST_DATE ($LATEST_COMMIT)" | \
    sudo tee "$WORKDIR/squashfs-root/etc/le-transplant-info" > /dev/null

log "Re-squashfs (~2 min)..."
sudo mksquashfs "$WORKDIR/squashfs-root" "$WORKDIR/SYSTEM" -comp xz -noappend

# ── 6. Check if --deploy ─────────────────────────────────────
if [ "${1:-}" != "--deploy" ]; then
    SIZE=$(du -h "$WORKDIR/SYSTEM" | cut -f1)
    log "Hybrid built: SYSTEM ($SIZE)"
    log "To deploy: $0 --deploy"
    echo ""
    echo "Files in $WORKDIR:"
    ls -lh "$WORKDIR"/{kernel.img,SYSTEM,*.dtb}
    exit 0
fi

# ── 7. Deploy to crackberry5 ──────────────────────────────────
log "Deploying to $DEPLOY_HOST..."

# Backup current /flash
ssh "$DEPLOY_USER@$DEPLOY_HOST" "
    mount -o remount,rw /flash
    mkdir -p /storage/backup-flash-\$(date +%Y%m%d-%H%M)
    cp /flash/kernel.img /flash/SYSTEM /flash/*.dtb /storage/backup-flash-\$(date +%Y%m%d-%H%M)/
    cp -r /flash/overlays /storage/backup-flash-\$(date +%Y%m%d-%H%M)/ 2>/dev/null
" || { err "SSH backup failed"; exit 1; }

# Upload kernel + SYSTEM + DTBs
scp "$WORKDIR/kernel.img" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" || { err "kernel.img upload failed"; exit 1; }
scp "$WORKDIR/SYSTEM" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" || { err "SYSTEM upload failed"; exit 1; }
scp "$WORKDIR"/*.dtb "$DEPLOY_USER@$DEPLOY_HOST:/flash/" 2>/dev/null || true
scp -r "$WORKDIR/overlays" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" 2>/dev/null || true

# Marker + reboot
ssh "$DEPLOY_USER@$DEPLOY_HOST" "
    echo '$LATEST_DATE-$LATEST_COMMIT' > $MARKER_FILE
    mount -o remount,ro /flash
    systemctl reboot
" || { err "Reboot failed"; exit 1; }

log "Deploy complete. Waiting 120s for reboot..."
sleep 120

# Verify
if ssh -o ConnectTimeout=10 "$DEPLOY_USER@$DEPLOY_HOST" "echo OK" 2>/dev/null; then
    log "✅ Transplant successful! System online."
else
    warn "⚠️  System not reachable after 120s — check manually."
fi
