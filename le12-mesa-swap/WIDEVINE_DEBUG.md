# Widevine DRM Testbild — Root Cause Analysis

**Date:** 2026-06-08
**System:** crackberry5 — LE12 (6.12.56 kernel) + LE13 (Kodi 22 userspace) hybrid

## Symptom

Widevine DRM playback (Crunchyroll) shows colored test pattern instead of video. Audio plays correctly. License acquisition and CDM initialization succeed.

## Root Cause

`system_heap.max_order=0` in the LE12 kernel command line limits DMA-heap allocations to 4 KB (order-0 pages only).

Widevine secure decode requires larger contiguous DMA buffers. With max_order=0, the CDM's single-sample decrypt test succeeds (small buffer), so ISA receives "Single decrypt possible" and uses the non-secure FFmpeg path. In the non-secure path, Widevine outputs test patterns instead of decrypted video frames.

On the LE13 kernel, larger DMA-heap allocations are available. The CDM detects the secure buffer capability, single-sample decrypt fails, and ISA falls back to the secure DRMPRIME path which renders actual video.

## Theories Ruled Out

- **NV12 missing from DRM planes:** Verified NV12, P010, YUV on ALL planes (Primary, Overlay, Cursor) via modetest
- **Mesa/GBM swap incorrect:** CDM loads, decrypts, and obtains licenses successfully
- **force_secure_decoder in ISA config:** Rejected by ISA 22.3.14.1 parser ("Unsupported config")
- **Pi 5 hardware limit:** LE13 kernel works without test pattern on the same hardware
- **Widevine CDM version:** CDM 4.10.2662.3 is current; offered update was older

## Evidence Chain

1. `/proc/cmdline` contains `system_heap.max_order=0`
2. `/dev/dma_heap/` only has `linux,cma` and `system` — no secure heap
3. ISA log: `GetCapabilities: Single decrypt possible`
4. ISA log: `CVideoPlayerVideo::OpenStream - open stream with codec id: 27` (FFmpeg H.264, not DRMPRIME)
5. ISA log: `Resolution max for secure decoder: 0x0` — secure path disabled
6. DRM plane inspection: NV12 available on all planes — not a format issue

## Fix

Change `system_heap.max_order=0` to `system_heap.max_order=10` in the kernel command line.

This allows DMA-heap allocations up to 4 MB (order-10 = 2^10 pages = 4096 * 4KB = 4 MB), sufficient for Widevine secure decode buffers.

### Deployment

```bash
# On crackberry5
mount -o remount,rw /flash
sed -i 's/system_heap.max_order=0/system_heap.max_order=10/' /flash/cmdline.txt
# If not present, add it before "quiet":
# sed -i 's/ quiet/ system_heap.max_order=10 quiet/' /flash/cmdline.txt
mount -o remount,ro /flash
# Then restart the system
```

### Verification

After restart, check Kodi log for:
```
GetCapabilities: Single decrypt failed, secure path only
```

And video codec should show DRMPRIME instead of FFmpeg.

## Status

- Root cause: **Identified** (2026-06-08)
- Fix: **Pending deployment/test**
