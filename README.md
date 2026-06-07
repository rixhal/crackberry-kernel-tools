# Crackberry Kernel Tools

Kernel extraction, backup, and restore tools for LibreELEC on Raspberry Pi 5.

## Context

**Problem:** LibreELEC 13 Nightly (kernel 6.18.32) has a V3D-MMU regression that breaks video playback on RPi5:
```
v3d 1002000000.v3d: MMU error from client L2T (40) at 0x1228ab00, pte invalid
```
→ Testbild statt Video, oder Systemcrash.

**Solution:** LE12-Kernel-Transplant — LE12 stable SYSTEM (kernel 6.12.56) mit LE13 /storage (Kodi 21, alle Addons).

**Status: ✅ FUNKTIONIERT** (seit 2026-06-04 im Produktivbetrieb)

- V3D-MMU: keine Errors ✅
- WiFi: verbunden, -51 dBm ✅
- LAN: funktioniert ✅
- Kodi 21 + alle Addons (Samsung TV Plus, VavooTV, Flatpak) ✅
- Tailscale ✅
- Keine Crashes bei H.264-Playback ✅

## So funktioniert's

LE12-SYSTEM (SquashFS) stellt Kernel 6.12.56 + Module + Firmware.
LE13-/storage stellt Kodi 21, Addons, Flatpak, alle Userdaten.

Kein Kernel-Mixing-Hack nötig — einfach das komplette LE12-SYSTEM deployen,
/storage unangetastet lassen. Die Kernel-Module passen perfekt zum laufenden Kernel,
weil sie aus dem gleichen SYSTEM-Image kommen.

## Deployment (durchgeführt 2026-06-04)

### 1. LE13 Boot-Files backupen
```bash
ssh root@10.10.10.140 "
  mount -o remount,rw /flash
  mkdir -p /storage/le13-backup-boot
  cp /flash/kernel.img /flash/SYSTEM /flash/*.dtb /flash/hat_map.dtb /storage/le13-backup-boot/
  cp -r /flash/overlays /storage/le13-backup-boot/
"
```

### 2. LE12.2.1 Stable downloaden + SYSTEM deployen
```bash
wget https://releases.libreelec.tv/LibreELEC-RPi5.aarch64-12.2.1.img.gz
gunzip LibreELEC-RPi5.aarch64-12.2.1.img.gz

# Mounten
sudo losetup -f --show LibreELEC-RPi5.aarch64-12.2.1.img  # → /dev/loop0
sudo partprobe /dev/loop0
sudo mount /dev/loop0p1 /mnt/le12-boot

# Auf crackberry5 deployen (dauert ~2min)
scp /mnt/le12-boot/kernel.img /mnt/le12-boot/SYSTEM root@10.10.10.140:/flash/
scp /mnt/le12-boot/*.dtb root@10.10.10.140:/flash/
scp -r /mnt/le12-boot/overlays root@10.10.10.140:/flash/

# Reboot
ssh root@10.10.10.140 "mount -o remount,ro /flash && systemctl reboot"
```

### 3. Nach Reboot (~2min warten)
System bootet mit LE12-Kernel. WiFi braucht beim ersten Mal ~30s länger.
Danach alles normal.

## Rollback zu LE13
```bash
ssh root@10.10.10.140 "
  mount -o remount,rw /flash
  cp /storage/le13-backup-boot/kernel.img /flash/
  cp /storage/le13-backup-boot/SYSTEM /flash/
  cp /storage/le13-backup-boot/*.dtb /flash/
  cp -r /storage/le13-backup-boot/overlays /flash/
  mount -o remount,ro /flash
  systemctl reboot
"
```

## Backup (aktueller Zustand)
```bash
# /flash backup
ssh root@10.10.10.140 "
  mount -o remount,rw /flash
  tar czf /storage/backup-flash-le12-$(date +%Y%m%d).tar.gz -C /flash .
  mount -o remount,ro /flash
"

# Kodi config backup
ssh root@10.10.10.140 "
  tar czf /storage/backup-kodi-$(date +%Y%m%d).tar.gz \
    -C /storage/.kodi userdata/ \
    --exclude='userdata/Thumbnails' --exclude='userdata/Database'
"
```

## Scripts

- `extract-le-kernel.sh` — Extract kernel.img, DTBs, overlays, modules from LE image
- `backup-kernel.sh` — Backup current kernel from running LE system
- `restore-kernel.sh` — Restore backed-up kernel files to /flash

## Pitfalls

- **Nie nur kernel.img tauschen ohne SYSTEM** — Module passen nicht → Boot-Failure
- **Reboot dauert beim ersten Mal länger** — WiFi-Firmware-Neuladen
- **LE13-/storage bleibt erhalten** — alle Addons und Configs überleben
- **Rollback jederzeit möglich** — LE13-Backup liegt in /storage/le13-backup-boot/
