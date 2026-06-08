# LE12 Mesa Full Swap — Widevine Secure Video Fix

## Problem

LE13 nightly-20260607 (Mesa 26.1.2) broke the previous GBM-only swap fix.
LE12 `dri_gbm.so` needs `libgallium-25.1.9.so` — not present in LE13 (has `libgallium-26.1.2.so`).
SONAME mismatch prevents the old GBM-only swap from working.

Additionally, partial swap (dri_gbm + libgbm only, keeping LE13 EGL/GLES) causes
`EGL_NOT_INITIALIZED` because LE12 GBM isn't ABI-compatible with LE13 EGL.

## Solution: Full LE12 Mesa Swap

All four Mesa libs from LE12 + libgallium-25.1.9.so injected via fake Kodi addon.

| Library | LE12 Size | LE13 Size |
|---------|-----------|-----------|
| `dri_gbm.so` | 68 KB | 135 KB |
| `libgbm.so` | 68 KB | 68 KB |
| `libEGL.so` | 332 KB | 334 KB |
| `libGLESv2.so` | 67 KB | 67 KB |
| `libgallium-25.1.9.so` | 14.5 MB | — |

## LD_LIBRARY_PATH Injection

`/etc/profile.d/98-busybox.conf` clobbers `LD_LIBRARY_PATH` to `/usr/lib`.
But `99-kodi.conf` auto-appends addon lib directories containing `.so` files.

**Trick:** Create fake addon `/storage/.kodi/addons/mesa-le12/lib/` with symlink
`libgallium-25.1.9.so -> /storage/libgallium-25.1.9.so`. 99-kodi.conf detects the
`.so` file and adds the directory to `LD_LIBRARY_PATH`.

## Deploy

### 1. Extract LE12 libs from SYSTEM squashfs

```bash
mkdir -p /tmp/le12-mnt
mount -o loop,ro /storage/le12-from-backup/SYSTEM /tmp/le12-mnt

cp /tmp/le12-mnt/usr/lib/gbm/dri_gbm.so /storage/dri_gbm_le12_orig.so
cp /tmp/le12-mnt/usr/lib/libgbm.so.1.0.0 /storage/libgbm_le12_orig.so
cp /tmp/le12-mnt/usr/lib/libgallium-25.1.9.so /storage/libgallium-25.1.9.so
# EGL/GLES already extracted earlier — see script

umount /tmp/le12-mnt
```

### 2. Create fake addon for libgallium injection

```bash
mkdir -p /storage/.kodi/addons/mesa-le12/lib
ln -sf /storage/libgallium-25.1.9.so /storage/.kodi/addons/mesa-le12/lib/libgallium-25.1.9.so
```

### 3. Bind-mount + autostart.sh

See `autostart.sh` in this directory. The bind-mounts must happen BEFORE Kodi starts.

### 4. Verification

```bash
# Check LE12 libs active (sizes!)
ls -la /usr/lib/gbm/dri_gbm.so /usr/lib/libgbm.so.1.0.0 /usr/lib/libEGL.so.1.0.0 /usr/lib/libGLESv2.so.2.0.0
# Expected: dri_gbm=68608, libgbm=68056, libEGL=331728, libGLESv2=67288

# Check libgallium loaded
cat /proc/$(pidof kodi.bin)/maps | grep libgallium-25.1.9
```

## Known Limitation

Even with full Mesa swap, **`Resolution max for secure decoder: 0x0`** persists.
ISA (InputStream Adaptive 22.3.14.1) detects that the DRM display plane only supports
`AR24/LINEAR` — no `NV12` format. DRMPRIME secure decode requires NV12 for zero-copy
buffer sharing. Without NV12, ISA disables the secure decode path.

**Result:** Widevine decrypts successfully, but test pattern plays instead of video (audio works).
This is an LE12 kernel limitation — the LE12 kernel V3D driver doesn't expose NV12 on
the display plane. Rolling back to LE13 kernel restores Widevine playback, but V3D-MMU
crashes return.

## Notes

- Tested on: crackberry5 (LE13 nightly-20260607 userspace + LE12 6.12.56 kernel)
- Kodi 22, ISA 22.3.14.1, Widevine CDM 4.10.2662.3
- InputstreamHelper offered CDM downgrade (declined) — current CDM is newer
