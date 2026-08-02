# Embedded Gemma E4B results

> **Historical evidence note:** Build timings below are the 14:36 EDT snapshot. The later physical phone route uses the disclosed local pixel-facts → Gemma text bridge documented in `DEVICE_INFERENCE_REPORT.md`; raw-image physical Gemma remains blocked.

Updated: 2026-08-01 14:36 EDT (America/New_York)

## Exact configuration

- Model: `litert-community/gemma-4-E4B-it-litert-lm`
- Artifact: `gemma-4-E4B-it.litertlm`
- Artifact revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- LiteRT-LM revision: `f73637c57f0940b53da184e0d5adfc52a4e55eef`
- Source: ignored `work/models/gemma-4-E4B-it.litertlm`
- Exact bytes: `3,659,530,240`
- SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- Scheme/configuration: `GITimeline Hackathon` / `Hackathon`
- Bundle path: `EmbeddedModels/gemma-4-E4B-it.litertlm`
- Historical raw-image physical experiment: GPU engine / non-nil CPU vision, `vision_70` (`visualTokenBudget=70`), `maxNumTokens=1024`; this path remained blocked
- Published physical bridge: CPU engine / vision disabled / local bounded pixel facts / `maxNumTokens=2048`
- Arm64 Simulator exception: CPU engine / CPU vision

## Build evidence

| Check | Result |
| --- | --- |
| Full optimized signed build | **PASS** in 45.56 s |
| Current-source incremental rebuild | **PASS** in 14.87 s |
| Bundle/signature/architecture | **PASS:** `com.omairmkhan.GITimeline.debug`, strict signature, arm64 |
| Model count and identity | **PASS:** exactly one file, exact bytes/SHA-256, matching receipt |
| App size | **3,619,184 KiB** |
| Production configuration | **PASS:** `-O` whole-module, testability off, debug dylib off |
| Production-surface isolation | **PASS:** no preview, UI-test, fake-provider, import, bypass, or visible lab surface |
| Failure shields | **PASS:** missing model, wrong size, and wrong hash each fail the build |
| Incremental behavior | **PASS:** verified unchanged output is reused |
| Ordinary Release | **PASS:** model-free, production bundle ID, no Hackathon/debug surface |
| Current embedded Simulator build/install | **PASS:** 43 s / 4 s |
| Current embedded Simulator real-Gemma smoke | **PASS:** brown=`BROWN`, green=`GREEN`, control=`OTHER`; structured 3/3 |
| Current embedded Simulator normal flow | **PASS:** automatic review, edit, save, History, exact provenance |
| Current embedded Simulator relaunch | **PASS:** reviewed edit, image, and provenance reopened |

The model weight remains ignored and is not staged or uploaded.

## Physical boundary

At this snapshot, an earlier embedded app had installed but the optimized current-source artifact had not. Later evidence documented the local pixel-facts → embedded Gemma text bridge through reviewed persistence. It did not prove raw-image physical Gemma or Airplane Mode operation.

```text
EMBEDDED_MODEL_BUILD: PASS
PHYSICAL_IPHONE_INSTALL: BLOCKED
PHYSICAL_GEMMA_IMAGE_INFERENCE: BLOCKED
AUTO_ANALYSIS_NORMAL_FLOW: PASS
NATIVE_REFERENCE_UI: PASS
SAVE_RELAUNCH: PASS
OFFLINE_IPHONE: BLOCKED
HACKATHON_DEMO_READY: NO
```

The two nonphysical flow fields above are supported by current-source arm64 Simulator evidence; they do not imply physical execution. Model preparation took 6.18 seconds. Six real image calls took 5.54–8.61 seconds; brown/green/control differed, strict structured output passed 3/3 without repair, the normal flow edited `form` to `mushy`, and relaunch reopened the same reviewed observation, image, and exact model/backend provenance. See `EMBEDDED_SIMULATOR_SMOKE.json`, `EMBEDDED_SIMULATOR_NORMAL_FLOW.json`, and `EMBEDDED_SIMULATOR_RELAUNCH.json`.

`HACKATHON_DEMO_READY` cannot become `YES` until every preceding physical/offline gate passes.

## One next owner action

Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. Once it appears in Xcode, install the current optimized artifact without uninstalling, then run the three bounded synthetic acceptance stages documented in `DEMO_RUNBOOK.md`.
