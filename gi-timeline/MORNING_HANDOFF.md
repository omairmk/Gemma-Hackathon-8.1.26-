# GI Timeline completion handoff

Updated: 2026-08-01 14:40 EDT (America/New_York)

## 1. What works now

The exact Gemma 4 E4B model now arrives inside the dedicated `GITimeline Hackathon` app. The optimized arm64 iPhone artifact is signed and passes strict model, receipt, bundle, architecture, and production-surface checks. The native photo → Reading photo → editable review → review-gated save → History → Detail flow passes the current app and UI suites, including smaller-screen dark mode at Accessibility Extra Large. Ordinary Release stays model-free.

Fresh current-source embedded Simulator evidence proves real E4B content dependence and the complete automatic review/edit/save/History/relaunch path. The optimized artifact has not been installed or launched on the physical iPhone because the phone is currently absent from Xcode's device list.

## 2. What is real Gemma versus a test mock

The embedded acceptance harness uses the exact LiteRT-LM image-plus-text runtime, model descriptor, image sanitizer, strict parser, normal review view model, entry store, and SwiftData container. It does not use canned JSON or the UI-test provider.

The UI screenshots and XCUITests use an explicit deterministic provider compiled only into Debug test surfaces. They prove the native journey, review rules, persistence, deletion, error recovery, and accessibility; they never satisfy a real-Gemma gate.

## 3. Exact model and execution location

- Model: `litert-community/gemma-4-E4B-it-litert-lm`
- Revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact: `gemma-4-E4B-it.litertlm`
- Bytes: `3,659,530,240`
- SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- LiteRT-LM: `f73637c57f0940b53da184e0d5adfc52a4e55eef`
- Physical policy: GPU engine / non-nil CPU vision
- Simulator exception: CPU engine / CPU vision

## 4. Whether real image pixels affected output

Yes in the current embedded arm64 Simulator build. Brown pixels returned `BROWN`, green pixels returned `GREEN`, and the geometric control returned `OTHER`; all three strict structured observations validated without repair, and the control produced `not_target_image`. Preparation took 6.18 seconds and the six image calls took 5.54–8.61 seconds. No physical-iPhone pixel-dependent output is claimed.

## 5. Physical iPhone result

The current optimized signed build passes. An earlier embedded build installed successfully without uninstalling, but the optimized current-source artifact has not been installed or launched because a fresh sanitized Xcode query returned no physical iOS devices. Physical Gemma image inference, reviewed persistence, and offline operation are blocked.

## 6. What can be tested immediately in under three minutes

Open the already prepared iPhone Simulator and launch GI Timeline. Walk through First Run and New Entry, then use the retained synthetic UI journey/screenshots to show Reading photo, Review, Save, History, Detail, and error recovery. The deterministic UI path is a presentation demo only; the separate JSON acceptance files and PASS markers are the authority for real Gemma.

For the physical build, select `GITimeline Hackathon` in Xcode, select the reconnected iPhone, and press Run. The 3.6 GB install may exceed three minutes and must not be described as instant.

## 7. One owner action

Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. Stop when it appears available in Xcode without an Unlock, Trust, Developer Mode, or developer-profile prompt.

## Honest status

```text
REAL_GEMMA_BACKEND: SIMULATOR_LOCAL
REAL_GEMMA_E2E: PASS
PHYSICAL_IPHONE_BUILD: PASS
NORMAL_APP_FLOW: PASS
UI_ACCEPTANCE: PASS
OFFLINE_IPHONE: BLOCKED
MORNING_LABEL: SIMULATOR_GEMMA_POC_GO

EMBEDDED_MODEL_BUILD: PASS
PHYSICAL_IPHONE_INSTALL: BLOCKED
PHYSICAL_GEMMA_IMAGE_INFERENCE: BLOCKED
AUTO_ANALYSIS_NORMAL_FLOW: PASS
NATIVE_REFERENCE_UI: PASS
SAVE_RELAUNCH: PASS
OFFLINE_IPHONE: BLOCKED
HACKATHON_DEMO_READY: NO
```

The two nonphysical PASS values in the second block are current-source Simulator evidence. The physical install, inference, and offline rows remain blocked, so the full Hackathon device contract is not ready. Neither block upgrades the legacy physical `DEVICE_INFERENCE_STATUS` or `APP_END_TO_END_STATUS` fields.

## Key evidence

- `EMBEDDED_GEMMA_RESULTS.md`
- `EMBEDDED_SIMULATOR_SMOKE.json`
- `EMBEDDED_SIMULATOR_NORMAL_FLOW.json`
- `EMBEDDED_SIMULATOR_RELAUNCH.json`
- `TEST_RESULTS.md`
- `DEVICE_INFERENCE_REPORT.md`
- `DEMO_RUNBOOK.md`
- `outputs/demo-screens/README.md`

The app is as complete as unattended automation allowed. Model weights, signing values, device identifiers, result bundles, private logs, and personal images are excluded from Git.
