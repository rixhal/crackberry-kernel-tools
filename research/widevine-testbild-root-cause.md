# Widevine DRM Testbild Debug — Root Cause Analysis

**Date:** 2026-06-08
**System:** crackberry5 (RPi5), LE12/6.12.56 kernel + LE13 userspace hybrid
**Symptom:** Widevine DRM shows test pattern instead of video (audio works)

## Root Cause

`system_heap.max_order=0` in kernel command line limits DMA-heap allocations to order-0
(4 KB pages only). Widevine CDM requires larger contiguous DMA buffers for secure decoding.

With max_order=0:
- `DecryptSampleData()` fails on allocation → error code 2
- CDM reports: `GetCapabilities: Single decrypt possible`
- ISA sets `Resolution max for secure decoder: 0x0`
- Kodi falls back to `CDVDVideoCodecFFmpeg` (non-secure path)
- CDM outputs test pattern to non-secure pipeline

Expected with fix (max_order=10, i.e. 4 MB max allocation):
- `DecryptSampleData()` succeeds
- CDM reports: `GetCapabilities: Single decrypt failed, secure path only`
- ISA enables secure decoder path → `DRMPRIME`
- Video renders correctly via DRM planes

## Theories Investigated (all disproven)

| Theory | Finding |
|---|---|
| V3D DRM plane missing NV12 format | **False** — NV12/P010/YUV present on all planes via `modetest -M vc4` |
| Mesa LE12 swap incorrect | **False** — CDM decrypts successfully, license acquired |
| `force_secure_decoder` in ISA config | **Rejected** by ISA 22.3.14.1: "Unsupported config" |
| `stream_selection_type=force_secure_decoder` | Causes Kodi crash (CDM path fails under max_order=0) |
| IOMMU missing | **False** — `bcm2712_iommu` active in cmdline |
| Widevine CDM version too old | **False** — 4.10.2662.3 is current |
| Pi 5 hardware limit | **False** — LE13 kernel works (but has V3D-MMU crashes) |

## The DMA Buffer Path

```
Widevine CDM DecryptSampleData()
    → DMA-HEAP allocation (system heap)
    → vc4 V3D DRM secure buffer
    → DRMPRIME rendering to NV12 plane

With max_order=0: step 1 fails → CDM falls back to non-secure
```

## Fix

Add `system_heap.max_order=10` to kernel command line in `/flash/cmdline.txt`:

```
# Before
reboot=w coherent_pool=1M ... system_heap.max_order=0 ...

# After
reboot=w coherent_pool=1M ... system_heap.max_order=10 ...
```

This allows DMA-heap allocations up to order-10 (4 MB per allocation),
sufficient for Widevine secure decode buffer requirements.

## Verification Steps

1. Check `/proc/cmdline` shows `system_heap.max_order=10`
2. Play Crunchyroll DRM content
3. Log should show: `Single decrypt failed, secure path only`
4. Log should show: `CDVDVideoCodecDRMPRIME` instead of `CDVDVideoCodecFFmpeg`
5. Video renders correctly (no test pattern)

## Related Files

- `/flash/cmdline.txt` — kernel command line (needs `system_heap.max_order=10`)
- `/dev/dma_heap/system` — system DMA heap (limited by max_order)
- `/dev/dma_heap/linux,cma` — CMA DMA heap (512 MB reserved)
- Kernel: `drivers/dma-buf/heaps/system_heap.c` — `system_heap.max_order` parameter

## Known Limitations

- LE13 kernel works with Widevine but has V3D-MMU crashes making it unstable
- The `system_heap.max_order=0` default likely exists as workaround for a DMA fragmentation bug
  in the 6.12-era BCM2712 kernel. Setting it to 10 may expose that bug if WARN_ONs appear
  in dmesg.
- If CMA exhaustion occurs with max_order=10, the system may become unstable under heavy
  GPU load — but the 512 MB CMA reservation should suffice.
