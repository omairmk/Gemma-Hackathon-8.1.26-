# GI Timeline — Gemma 4 on-device healthcare proof of concept

This is the public source-of-truth repository for the GI Timeline submission to [Build with Gemma NYC: On-Device AI for Healthcare](https://www.kaggle.com/competitions/build-with-gemma-nyc-on-device-ai-for-healthcare/overview). The competition implementation is the native iOS project under [`gi-timeline/`](gi-timeline/).

GI Timeline is a decision-support documentation prototype. It does not diagnose, recommend treatment, or replace professional medical care. All committed fixtures and screenshots are synthetic; no patient data or real health photographs belong in this repository.

## Post-event correction to the Kaggle writeup

The attached Kaggle writeup described direct raw-photo Gemma inference, 5.7–9.1-second raw-photo CPU timings, and verified Airplane Mode operation as physical-iPhone results. The retained source and evidence do not support those three phone claims. The accurate record is:

- Direct raw-photo Gemma and the recorded raw-image timings were **arm64 iPhone Simulator** evidence.
- The physical iPhone used local pixel facts followed by real embedded Gemma 4 E4B **text inference**; Gemma did not receive the raw photo.
- Physical Airplane Mode operation was **not verified**.

This repository intentionally publishes the corrected architecture and evidence boundary.

## Exact implementation boundary

| Path | What is verified | What is not claimed |
| --- | --- | --- |
| Arm64 iPhone Simulator | The exact Gemma 4 E4B model received raw synthetic image pixels through LiteRT-LM, produced content-dependent output, and completed editable review → save → History → relaunch. | Simulator evidence is not physical-iPhone or offline proof. |
| Physical iPhone | A signed build used an on-device 12×12 pixel-facts extractor, then the exact embedded Gemma 4 E4B model in text-only mode to produce a strict, reviewable draft. The normal review/save/History/relaunch flow was documented as passing. | The raw photo was **not** sent to Gemma. Physical raw-image LiteRT vision remained blocked. Airplane Mode was not verified. |

The retained device evidence does not tie the installed binary to a Git commit or byte-for-byte source archive. This publication therefore provides the source needed to reproduce the documented phone bridge, but does not claim that this commit is the exact installed binary.

## How Gemma 4 is core to the phone flow

1. The selected image stays on the device.
2. `LocalPixelFacts` deterministically extracts a bounded coarse color/shape/quality summary from the image pixels.
3. The exact embedded Gemma 4 E4B model receives those facts through LiteRT-LM and generates the five-field structured observation draft.
4. A strict parser validates the response. Every field remains visibly suggested until the user confirms or edits it.
5. Save is blocked until human review is complete; reviewed data then persists locally in SwiftData.

The local extractor materially affects the result and is disclosed in the UI and provenance. See [`InferenceService.swift`](gi-timeline/GITimeline/InferenceService.swift), [`ModelRuntime.swift`](gi-timeline/GITimeline/ModelRuntime.swift), and the [physical-device report](gi-timeline/DEVICE_INFERENCE_REPORT.md).

## Exact model and runtime

- Model: [`litert-community/gemma-4-E4B-it-litert-lm`](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)
- Model revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact: `gemma-4-E4B-it.litertlm`
- Size: `3,659,530,240` bytes
- SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- Runtime: [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`

Model weights are intentionally excluded from Git. Obtain the artifact from its official model page, review its license, place it at `work/models/gemma-4-E4B-it.litertlm`, and verify the pinned size and digest before building. The dedicated build script fails closed when the artifact is missing or mismatched.

## Build and test

Requirements: macOS on Apple silicon, Xcode with an iOS 17-or-newer SDK, and enough free space for the 3.66 GB source model plus the copied app resource and build cache.

```sh
git clone https://github.com/omairmk/Gemma-Hackathon-8.1.26-.git
cd Gemma-Hackathon-8.1.26-/gi-timeline

# Core parser/state-machine tests; no model required.
swift test

# Verify the separately downloaded model before using the Hackathon scheme.
stat -f '%z' ../work/models/gemma-4-E4B-it.litertlm
shasum -a 256 ../work/models/gemma-4-E4B-it.litertlm

# Then open GITimeline.xcodeproj and select the shared
# "GITimeline Hackathon" scheme.
open GITimeline.xcodeproj
```

For a physical build, select your own Apple development team locally in Xcode; signing identifiers and provisioning material are intentionally not committed. The [demo runbook](gi-timeline/DEMO_RUNBOOK.md) contains command-line build and synthetic-only acceptance steps.

## Repository guide

- [`gi-timeline/README.md`](gi-timeline/README.md) — native-app status and architecture
- [`gi-timeline/DEVICE_INFERENCE_REPORT.md`](gi-timeline/DEVICE_INFERENCE_REPORT.md) — physical runtime boundary
- [`gi-timeline/TEST_RESULTS.md`](gi-timeline/TEST_RESULTS.md) — regression commands and historical evidence
- [`assets/ATTRIBUTION_AND_SYNTHETIC_DATA.md`](assets/ATTRIBUTION_AND_SYNTHETIC_DATA.md) — model/runtime attribution and data provenance
- [`NOTICE`](NOTICE) — third-party attribution

The separate `gi-journal/` directory is an earlier exploratory fallback and is not the source of the submitted native iPhone experience.

## License

Project-authored source is licensed under [Apache License 2.0](LICENSE). Model weights are not included and remain subject to their own distribution terms. Apple SDK components are not redistributed by this repository.
