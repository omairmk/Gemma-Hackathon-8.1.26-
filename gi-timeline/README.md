# GI Timeline

Native SwiftUI + SwiftData hackathon proof of concept for a private, review-first GI record. A photo triggers local structured image analysis, the user confirms or edits every proposed observation, and only then can the entry be saved to History.

## Current status

- `GITimeline Hackathon` embeds the exact pinned Gemma 4 E4B artifact after strict build-time verification.
- Fresh current-source arm64 Simulator evidence passes real brown/green/control inference, strict structured output, automatic review/edit/save/History, and terminate/relaunch persistence.
- Host tests pass 14/14, app tests pass 37/37, and the final exact-current UI suite passes 3/3.
- Seven native screens plus the recoverable error state pass dark/Accessibility Extra Large visual inspection.
- The optimized signed arm64 iPhone artifact passes signature, bundle, model, receipt, and production-surface audits.
- Ordinary Release remains model-free and excludes Hackathon/debug surfaces.
- The optimized physical install, physical image inference, physical persistence, and Airplane Mode gates are blocked because no physical iOS device is currently visible to Xcode.

This supports `SIMULATOR_GEMMA_POC_GO`. It does not prove physical-iPhone or offline operation. Legacy `DEVICE_INFERENCE_STATUS` and `APP_END_TO_END_STATUS` remain unchanged.

## Exact model

- `litert-community/gemma-4-E4B-it-litert-lm`
- Revision `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact `gemma-4-E4B-it.litertlm`
- 3,659,530,240 bytes
- SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- LiteRT-LM `f73637c57f0940b53da184e0d5adfc52a4e55eef`

The model lives under ignored `work/models/` and is never committed or uploaded.

## Start here

- `MORNING_HANDOFF.md` — plain-English current truth.
- `DEMO_RUNBOOK.md` — build, demo, physical harness, and Airplane Mode steps.
- `TEST_RESULTS.md` — current regression matrix and reproduction commands.
- `EMBEDDED_GEMMA_RESULTS.md` — exact model/build/runtime evidence.
- `DEVICE_INFERENCE_REPORT.md` — physical-only boundary.
- `outputs/demo-screens/README.md` — sanitized synthetic UI evidence.

## One owner action

Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. Once it appears available in Xcode without an owner prompt, the current optimized artifact can be installed without uninstalling and the physical synthetic acceptance sequence can resume.

Prototype only — not medical advice.
