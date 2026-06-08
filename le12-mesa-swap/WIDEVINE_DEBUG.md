# Widevine DRM Testbild — Root Cause Analysis

**Status: UNRESOLVED** (2026-06-08)
**Symptom:** Crunchyroll-Wiedergabe zeigt Testbild statt Video (Audio läuft)

## Endergebnis

**Root Cause:** Kein verfügbarer Kernel für Raspberry Pi 5 stellt `/dev/dma_heap/reserved` bereit. Dieses Device wird vom Widevine CDM für die Zuweisung sicherer DMA-Puffer benötigt, die wiederum für den **Secure-Decode-Pfad** zwingend sind.

## Getestete Ansätze

| Ansatz | Ergebnis |
|--------|----------|
| **LE12 Stabil** (Kernel 6.12.56, Kodi 21, ISA 21.5.18) | Testbild — kein `dma_heap/reserved` |
| **LE13 Nightly** (Kernel 6.18.32, Kodi 22, ISA 22.3.14.1) | Testbild — kein `dma_heap/reserved` |
| **ISA Patch: SECURE_PATH + ANNEXB_REQUIRED + SECURE_DECODER** (Capabilities erzwingen) | Testbild — CDM scheitert ohne reserved heap |
| **ISA Patch: force_secure_decoder Parsing in manifest_config** | Testbild — CDM scheitert ohne reserved heap |
| **LE13 Hybrid: LE13 Userspace + LE12 Kernel** | Testbild — selbe Limitierung |
| **LE12 Hybrid: LE12 Userspace + LE13 Kernel** | V3D-MMU-Crashes |

## Detaillierte Findings

### 1. DMA Heap Status auf allen Systemen

**LE12 (Kernel 6.12.56):**
```
/dev/dma_heap/default_cma_region
/dev/dma_heap/linux,cma
/dev/dma_heap/system
```

**LE13 (Kernel 6.18.32):**
```
/dev/dma_heap/default_cma_region
/dev/dma_heap/linux,cma
/dev/dma_heap/system
```

**Fehlend auf BEIDEN:** `/dev/dma_heap/reserved` — nur mit `CONFIG_DMABUF_HEAPS_RESERVED=y` im Kernel verfügbar.

### 2. CDM Verhalten

Ohne `dma_heap/reserved`:
- CDM initialisiert erfolgreich
- Lizenzaustausch funktioniert
- `GetCapabilities: Single decrypt possible` — CDM fällt auf Software-Decrypt zurück
- Decodierte Frames landen in nicht-securem Speicher → Testbild

Mit `dma_heap/reserved` (auf korrekt konfigurierten Systemen):
- CDM kann Secure-Buffer anfordern
- `GetCapabilities: Secure path only` — CDM weigert sich, Software-Decrypt zu nutzen
- ISA aktiviert DRMPRIME-Secure-Pfad
- Video wird korrekt dargestellt

### 3. ISA-Patches (alle erfolglos ohne dma_heap/reserved)

Im Branch/Repository unter `patches/`:

**Patch 1: CDM Capabilities erzwingen**
```
src/decrypters/widevine/WVCencSingleSampleDecrypter.cpp
Zeile 164: caps.flags = SUPPORTS_DECODING | SECURE_PATH | ANNEXB_REQUIRED | SECURE_DECODER
```

**Patch 2: manifest_config force_secure_decoder Parsing**
```
src/CompKodiProps.h — ManifestConfig::forceSecureDecoder hinzugefügt
src/CompKodiProps.cpp — force_secure_decoder Handler in ParseManifestConfig
src/decrypters/DrmEngine.cpp — forceSecureDecoder → isForceSecureDecoder override
```

### 4. Warum Patches allein nicht reichen

Selbst wenn man SECURE_PATH erzwingt:
1. CDM fragt bei `DecryptSampleData()` einen Secure-Buffer an
2. Secure-Buffer-Allokation geht zu `/dev/dma_heap/reserved`
3. Device existiert nicht → Allokation schlägt fehl
4. CDM returned `kNeedMoreData` (keine Frames)
5. Oder CDM returned Status 14 (kFailedWithAdditionalData)

Der CDM Binary-Blob (libwidevinecdm.so) kann nicht gepatcht werden. Er HAT secure Buffer allocation fest verdrahtet auf `dma_heap/reserved`.

## Lösungsoptionen

### Option A: Kernel mit CONFIG_DMABUF_HEAPS_RESERVED bauen (empfohlen)

```
Kernel Config:
CONFIG_DMABUF_HEAPS_RESERVED=y
```

D.h. LibreELEC-Kernel selbst bauen mit aktiviertem Flag. Der Treiber ist in `drivers/dma-buf/dma-heap-reserved.c` und reserviert einen Speicherbereich, den die VideoCore-Firmware für sichere Framebuffer nutzt.

**Aufwand:** Mittel — LE13-Quellen + `menuconfig` + Cross-Compiler für aarch64 auf Pi5.

### Option B: Kenndo Kernel-Modul für dma_heap/reserved bauen

Falls der Treiber als Modul gebaut werden kann (`CONFIG_DMABUF_HEAPS_RESERVED=m`). Prüfen: aktuell nicht als Modul im LE13-Kernel vorhanden.

### Option C: LE13 Native abwarten bis nächste Nightly das Flag setzt

Der LE13-Kernel 6.18.21+ hatte es nicht. Möglicherweise wird es in zukünftigen Nightlys aktiviert. Regelmäßig checken: `ls /dev/dma_heap/` auf `reserved`.

## Gelernte Lektionen

1. **ISA-Patches sind nutzlos ohne Kernel-Unterstützung** — Die Pipeline von CDM → Kernel DMA → V3D muss intakt sein
2. **LE13 Kernel (6.18.x) und LE12 Kernel (6.12.x) haben identisches DMA-Profiling** — Beide vermissen `dma_heap/reserved`
3. **LE13 bootet stabil auf Pi5** — Kein V3D-MMU-Problem mehr mit Kernel 6.18.32 (Gültig ab 2026-06-02 Nightly)
4. **`force_secure_decoder: true`** in Crunchyrolls manifest_config wird von ISA erkannt, aber CDM kann nicht reagieren ohne Kernel-Support

## Nächste konkrete Schritte

1. LE13 läuft stabil auf crackberry5 — Kodi 22 + alle Addons funktionieren ✅
2. Kernel bauen mit `CONFIG_DMABUF_HEAPS_RESERVED=y`
3. CDM Secure-Decode testen
4. Wenn erfolgreich → komplette LE13 Migration (kein LE12-Transplant mehr nötig)
