# Widevine DRM Testbild Debug — Root Cause Analyse

**Datum:** 2026-06-08
**System:** crackberry5 (RPi5), LE12/6.12.56 Kernel + LE13 Userspace Hybrid
**Symptom:** Widevine DRM zeigt Testbild statt Video (Audio läuft)

## Root Cause

`system_heap.max_order=0` in der Kernel-Cmdline limitiert DMA-Heap-Allocations auf Order-0
(4 KB Pages). Das Widevine-CDM braucht größere zusammenhängende DMA-Buffer für Secure-Decoding.

Mit max_order=0:
- `DecryptSampleData()` schlägt fehl bei Allocation → Error-Code 2
- CDM meldet: `GetCapabilities: Single decrypt possible`
- ISA setzt `Resolution max for secure decoder: 0x0`
- Kodi fällt zurück auf `CDVDVideoCodecFFmpeg` (nicht-sicherer Pfad)
- CDM gibt Testbild auf die nicht-sichere Pipeline aus

Erwartet mit Fix (max_order=10, d.h. max 4 MB pro Allocation):
- `DecryptSampleData()` erfolgreich
- CDM meldet: `GetCapabilities: Single decrypt failed, secure path only`
- ISA aktiviert Secure-Decoder-Pfad → `DRMPRIME`
- Video wird korrekt via DRM-Planes gerendert

## Untersuchte Theorien (alle widerlegt)

| Theorie | Ergebnis |
|---|---|
| V3D DRM Plane hat kein NV12-Format | **Falsch** — NV12/P010/YUV auf allen Planes via `modetest -M vc4` |
| Mesa LE12 Swap inkorrekt | **Falsch** — CDM entschlüsselt erfolgreich, License geholt |
| `force_secure_decoder` in ISA-Config | **Abgelehnt** von ISA 22.3.14.1: "Unsupported config" |
| `stream_selection_type=force_secure_decoder` | Verursacht Kodi-Crash (CDM-Pfad scheitert unter max_order=0) |
| IOMMU fehlt | **Falsch** — `bcm2712_iommu` aktiv in cmdline |
| Widevine CDM Version zu alt | **Falsch** — 4.10.2662.3 ist aktuell |
| Pi-5-Hardware-Limit | **Falsch** — LE13-Kernel funktioniert (hat aber V3D-MMU-Crashes) |

## Der DMA-Buffer-Pfad

```
Widevine CDM DecryptSampleData()
    → DMA-HEAP Allocation (system heap)
    → vc4 V3D DRM Secure Buffer
    → DRMPRIME Rendering auf NV12 Plane

Mit max_order=0: Schritt 1 scheitert → CDM fällt zurück auf nicht-sicher
```

## Fix

`system_heap.max_order=10` zur Kernel-Cmdline in `/flash/cmdline.txt` hinzufügen:

```
# Vorher
reboot=w coherent_pool=1M ... system_heap.max_order=0 ...

# Nachher
reboot=w coherent_pool=1M ... system_heap.max_order=10 ...
```

Erlaubt DMA-Heap-Allocations bis Order-10 (4 MB pro Allocation),
ausreichend für Widevine-Secure-Decode-Buffer.

## Verifikation

1. Prüfen: `/proc/cmdline` zeigt `system_heap.max_order=10`
2. Crunchyroll-DRM-Content abspielen
3. Log sollte zeigen: `Single decrypt failed, secure path only`
4. Log sollte zeigen: `CDVDVideoCodecDRMPRIME` statt `CDVDVideoCodecFFmpeg`
5. Video rendert korrekt (kein Testbild)

## Relevante Dateien

- `/flash/cmdline.txt` — Kernel-Cmdline (braucht `system_heap.max_order=10`)
- `/dev/dma_heap/system` — System DMA Heap (limitiert durch max_order)
- `/dev/dma_heap/linux,cma` — CMA DMA Heap (512 MB reserviert)
- Kernel: `drivers/dma-buf/heaps/system_heap.c` — `system_heap.max_order` Parameter

## Bekannte Einschränkungen

- LE13-Kernel funktioniert mit Widevine, hat aber V3D-MMU-Crashes die ihn instabil machen
- Der `system_heap.max_order=0` Default existiert vermutlich als Workaround für einen
  DMA-Fragmentierungs-Bug im BCM2712-Kernel der 6.12-Ära. Auf 10 zu setzen könnte diesen
  Bug exponieren (WARN_ONs in dmesg).
- Falls CMA-Erschöpfung mit max_order=10 auftritt, könnte das System unter schwerer
  GPU-Last instabil werden — aber die 512 MB CMA-Reservierung sollte ausreichen.
