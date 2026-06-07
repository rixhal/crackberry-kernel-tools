#!/bin/bash
# build-le12-kernel-transplant.sh
# Baut einen Hybrid aus LE12-Kernel + LE13-Userspace für RPi5
# LE12-Kernel = stabiler V3D | LE13-SYSTEM = neueste Kodi-Addons
#
# Usage: ./build-le12-kernel-transplant.sh [--deploy]
#   Ohne --deploy: baut nur, zeigt Diff zur letzten Version
#   Mit --deploy: pushed auf crackberry5 und rebootet

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
    log "Aufräumen..."
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

# ── 1. Neueste Nightly finden ──────────────────────────────────
log "Suche neueste LE13 Nightly..."
LATEST=$(curl -sL "$LE13_BASE/" | grep -oP 'LibreELEC-RPi5.*?nightly-\d{8}-[a-f0-9]+\.img\.gz' | sort | tail -1)
if [ -z "$LATEST" ]; then
    err "Keine Nightly gefunden!"
    exit 1
fi
LATEST_DATE=$(echo "$LATEST" | grep -oP '\d{8}')
LATEST_COMMIT=$(echo "$LATEST" | grep -oP '[a-f0-9]{7}(?=\.img)')
log "Neueste Nightly: $LATEST_DATE ($LATEST_COMMIT)"

# ── 2. Prüfen ob Update nötig ─────────────────────────────────
CURRENT=$(ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_HOST" "cat $MARKER_FILE 2>/dev/null" 2>/dev/null || echo "none")
if [ "$CURRENT" = "$LATEST_DATE-$LATEST_COMMIT" ]; then
    log "Bereits aktuell ($CURRENT). Nichts zu tun."
    exit 0
fi
log "Update verfügbar: $CURRENT → $LATEST_DATE-$LATEST_COMMIT"

# ── 3. Images downloaden ───────────────────────────────────────
mkdir -p "$WORKDIR"
cd "$WORKDIR"

log "Download LE12.2.1 Stable..."
if [ ! -f le12.img ]; then
    curl -sL "$LE12_URL" -o le12.img.gz
    gunzip -f le12.img.gz
fi

LE13_URL="$LE13_BASE/$LATEST"
log "Download LE13 Nightly..."
curl -sL "$LE13_URL" -o le13.img.gz
gunzip -f le13.img.gz

# ── 4. LE12 Kernel + Module extrahieren ────────────────────────
log "Extrahiere LE12 Kernel + Module..."
sudo losetup -fP le12.img
LE12_LOOP=$(sudo losetup -j le12.img | grep -oP '/dev/loop\d+(?=:)' | head -1)
sudo mkdir -p /mnt/le12-boot /mnt/le12-system
sudo mount ${LE12_LOOP}p1 /mnt/le12-boot
sudo mount -o loop /mnt/le12-boot/SYSTEM /mnt/le12-system

# Kernel + DTBs kopieren
sudo cp /mnt/le12-boot/kernel.img "$WORKDIR/"
sudo cp /mnt/le12-boot/*.dtb "$WORKDIR/"
sudo cp -r /mnt/le12-boot/overlays "$WORKDIR/" 2>/dev/null || true

LE12_KERNEL_VER=$(sudo ls /mnt/le12-system/lib/modules/ | head -1)
log "LE12 Kernel-Version: $LE12_KERNEL_VER"

# Module sichern
sudo tar czf "$WORKDIR/le12-modules.tar.gz" -C /mnt/le12-system/lib/modules "$LE12_KERNEL_VER"

# ── 5. LE13 SYSTEM mounten + patchen ───────────────────────────
log "Extrahiere LE13 SYSTEM..."
sudo losetup -fP le13.img
LE13_LOOP=$(sudo losetup -j le13.img | grep -oP '/dev/loop\d+(?=:)' | head -1)
sudo mkdir -p /mnt/le13-boot /mnt/le13-system
sudo mount ${LE13_LOOP}p1 /mnt/le13-boot

LE13_KERNEL_VER=$(sudo unsquashfs -l /mnt/le13-boot/SYSTEM 2>/dev/null | grep 'lib/modules/' | head -1 | awk -F/ '{print $4}' || echo "unknown")

log "Patche LE13 SYSTEM (LE12-Module rein)..."
sudo unsquashfs -d "$WORKDIR/squashfs-root" /mnt/le13-boot/SYSTEM

# LE13 Module entfernen, LE12 Module reinkopieren
sudo bash -c "rm -rf $WORKDIR/squashfs-root/lib/modules/*"
sudo mkdir -p "$WORKDIR/squashfs-root/lib/modules"
sudo tar xzf "$WORKDIR/le12-modules.tar.gz" -C "$WORKDIR/squashfs-root/lib/modules/"

# Versions-Marker setzen
echo "LE12-Kernel: $LE12_KERNEL_VER | LE13-Nightly: $LATEST_DATE ($LATEST_COMMIT)" | \
    sudo tee "$WORKDIR/squashfs-root/etc/le-transplant-info" > /dev/null

log "Re-squashfs (dauert ~2min)..."
sudo mksquashfs "$WORKDIR/squashfs-root" "$WORKDIR/SYSTEM" -comp xz -noappend

# ── 6. Prüfen ob --deploy ─────────────────────────────────────
if [ "${1:-}" != "--deploy" ]; then
    SIZE=$(du -h "$WORKDIR/SYSTEM" | cut -f1)
    log "Hybrid gebaut: SYSTEM ($SIZE)"
    log "Zum Deployen: $0 --deploy"
    echo ""
    echo "Dateien in $WORKDIR:"
    ls -lh "$WORKDIR"/{kernel.img,SYSTEM,*.dtb}
    exit 0
fi

# ── 7. Deploy auf crackberry5 ──────────────────────────────────
log "Deploy auf $DEPLOY_HOST..."

# Backup aktueller /flash
ssh "$DEPLOY_USER@$DEPLOY_HOST" "
    mount -o remount,rw /flash
    mkdir -p /storage/backup-flash-\$(date +%Y%m%d-%H%M)
    cp /flash/kernel.img /flash/SYSTEM /flash/*.dtb /storage/backup-flash-\$(date +%Y%m%d-%H%M)/
    cp -r /flash/overlays /storage/backup-flash-\$(date +%Y%m%d-%H%M)/ 2>/dev/null
" || { err "SSH-Backup fehlgeschlagen"; exit 1; }

# Kernel + SYSTEM + DTBs hochladen
scp "$WORKDIR/kernel.img" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" || { err "kernel.img upload fehlgeschlagen"; exit 1; }
scp "$WORKDIR/SYSTEM" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" || { err "SYSTEM upload fehlgeschlagen"; exit 1; }
scp "$WORKDIR"/*.dtb "$DEPLOY_USER@$DEPLOY_HOST:/flash/" 2>/dev/null || true
scp -r "$WORKDIR/overlays" "$DEPLOY_USER@$DEPLOY_HOST:/flash/" 2>/dev/null || true

# Marker + Reboot
ssh "$DEPLOY_USER@$DEPLOY_HOST" "
    echo '$LATEST_DATE-$LATEST_COMMIT' > $MARKER_FILE
    mount -o remount,ro /flash
    systemctl reboot
" || { err "Reboot fehlgeschlagen"; exit 1; }

log "Deploy abgeschlossen. Warte 120s auf Reboot..."
sleep 120

# Verify
if ssh -o ConnectTimeout=10 "$DEPLOY_USER@$DEPLOY_HOST" "echo OK" 2>/dev/null; then
    log "✅ Transplant erfolgreich! System online."
else
    warn "⚠️  System nach 120s nicht erreichbar — ggf. manuell prüfen."
fi
