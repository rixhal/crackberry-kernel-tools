# Crackberry Kernel Tools

Kernel extraction, backup, and restore tools for LibreELEC on Raspberry Pi 5.

## Context

**Problem:** LibreELEC 13 Nightly (kernel 6.18.32) has a V3D-MMU regression that breaks hardware-accelerated video playback on RPi5:
```
v3d 1002000000.v3d: MMU error from client L2T (40) at 0x1228ab00, pte invalid
```

**Approach:** Kernel mixing — run LE12 stable kernel (6.12.87) with LE13 userspace (Kodi 21, Mesa 25).

**Result:** Partial success. Kernel boots, V3D works, but WiFi fails due to module/kernel API mismatch.

## Lesson Learned

Kernel mixing across major LE versions is fragile. The kernel and its modules form a tight ABI — mismatched userspace drivers (WiFi firmware loader, GPU firmware interface) break. Better strategy:

1. Fix cmdline.txt parameters (NUMa, IOMMU, CMA)
2. Try `dtoverlay` tweaks in config.txt
3. Find a LE13 Nightly build before the V3D regression
4. As last resort: full downgrade to LE12 stable

## Scripts

- `extract-le-kernel.sh` — Extract kernel.img, DTBs, overlays, and modules from a LibreELEC image
- `backup-kernel.sh` — Backup current kernel from a running LibreELEC system to SSD/storage
- `restore-kernel.sh` — Restore backed-up kernel files to /flash
```

## Files

- `le12-kernel-files.txt` — Inventory of LE12.2.1 kernel files used for the attempt
- `le13-backup-files.txt` — Inventory of LE13 backup files
