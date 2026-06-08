# Crackberry Kernel Tools

Kernel extraction, backup, restore, and transplant tools for LibreELEC on Raspberry Pi 5.

## Context

**Problem:** LibreELEC 13 Nightly (kernel 6.18.32) has a V3D-MMU regression that breaks video playback on RPi5:
```
v3d 1002000000.v3d: MMU error from client L2T (40) at 0x1228ab00, pte invalid
```
→ Test pattern instead of video, or system crash.

**Solution:** LE12 kernel transplant — LE12 stable SYSTEM (kernel 6.12.56) with LE13 `/storage` (Kodi 22, all addons).

**Status: ⚠️ PARTIALLY WORKING** (in production since 2026-06-04)

- V3D-MMU: no errors ✅
- WiFi: connected, -51 dBm ✅
- LAN: working ✅
- Kodi 22 + all addons (Samsung TV Plus, VavooTV, Flatpak) ✅
- Tailscale ✅
- No crashes during H.264 playback ✅
- **Widevine DRM: test pattern instead of video ❌** (Pi 5 hardware limit — see below)

## How It Works

The LE12 SYSTEM (SquashFS) provides kernel 6.12.56 + modules + firmware.
LE13 `/storage` provides Kodi 22, addons, Flatpak, and all user data.

No kernel mixing hacks needed — simply deploy the full LE12 SYSTEM,
leave `/storage` untouched. Kernel modules match the running kernel perfectly
because they come from the same SYSTEM image.

## Deployment (performed 2026-06-04)

### 1. Backup LE13 boot files
```bash
ssh root@10.10.10.140 "
  mount -o remount,rw /flash
  mkdir -p /storage/le13-backup-boot
  cp /flash/kernel.img /flash/SYSTEM /flash/*.dtb /flash/hat_map.dtb /storage/le13-backup-boot/
  cp -r /flash/overlays /storage/le13-backup-boot/
"
```

### 2. Download LE12.2.1 stable + deploy SYSTEM
```bash
wget https://releases.libreelec.tv/LibreELEC-RPi5.aarch64-12.2.1.img.gz
gunzip LibreELEC-RPi5.aarch64-12.2.1.img.gz

# Mount
sudo losetup -f --show LibreELEC-RPi5.aarch64-12.2.1.img  # → /dev/loop0
sudo partprobe /dev/loop0
sudo mount /dev/loop0p1 /mnt/le12-boot

# Deploy to crackberry5 (~2 min)
scp /mnt/le12-boot/kernel.img /mnt/le12-boot/SYSTEM root@10.10.10.140:/flash/
scp /mnt/le12-boot/*.dtb root@10.10.10.140:/flash/
scp -r /mnt/le12-boot/overlays root@10.10.10.140:/flash/

# Reboot
ssh root@10.10.10.140 "mount -o remount,ro /flash && systemctl reboot"
```

### 3. After reboot (wait ~2 min)
System boots with LE12 kernel. WiFi takes ~30s longer on first boot.
After that everything is normal.

## Rollback to LE13
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

## Backup (current state)
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
- `build-le12-kernel-transplant.sh` — Automated hybrid build (LE12 kernel + LE13 userspace)
- `le12-mesa-swap/` — LE12 Mesa full swap for Widevine secure video (see subdirectory)

## Pitfalls

- **Never swap only kernel.img without SYSTEM** — modules won't match → boot failure
- **First reboot takes longer** — WiFi firmware reload
- **LE13 /storage is preserved** — all addons and configs survive
- **Rollback always possible** — LE13 backup at /storage/le13-backup-boot/
- **VFAT quirks:** Always `busybox cp` to /flash, never `scp` directly. Run `busybox sync` after.

## Known Limitations

- **Widevine DRM playback shows test pattern** (audio works). LE12 kernel limitation:
  The LE12 kernel V3D driver only exposes `AR24/LINEAR` on the display plane,
  not `NV12`. DRMPRIME secure decode requires NV12 for zero-copy buffer sharing.
  Rolling back to LE13 kernel restores Widevine, but V3D-MMU crashes return.
  See `le12-mesa-swap/` for the Mesa swap workaround and details.
