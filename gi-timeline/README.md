# GI Timeline

Native SwiftUI + SwiftData hackathon proof of concept for a private, review-first GI record. A photo triggers local processing, the user confirms or edits every proposed observation, and only then can the entry be saved to History.

## Current status

- `GITimeline Hackathon` embeds the exact pinned Gemma 4 E4B artifact after strict build-time verification.
- Fresh current-source arm64 Simulator evidence passes real brown/green/control inference, strict structured output, automatic review/edit/save/History, and terminate/relaunch persistence.
- On the physical iPhone, LiteRT-LM 0.14's raw Gemma 4 vision executor still fails. The time-boxed phone build therefore uses a clearly disclosed local 12x12 color/shape map and the same embedded E4B in text-only mode; the raw photo is not sent to Gemma.
- A documented physical run passed the disclosed pixel-facts → Gemma text bridge through editable review, save, History, and terminate/relaunch persistence. The retained evidence does not identify the installed binary's exact Git commit.
- Host tests pass 14/14, app tests pass 41/41, and the final exact-current UI suite passes 3/3.
- Seven native screens plus the recoverable error state pass dark/Accessibility Extra Large visual inspection.
- The optimized signed arm64 iPhone artifact passes signature, bundle, model, receipt, and production-surface audits.
- Ordinary Release remains model-free and excludes Hackathon/debug surfaces.

This supports `SIMULATOR_GEMMA_POC_GO` for real multimodal Gemma and `PHYSICAL_HACKATHON_BRIDGE_GO` for the disclosed iPhone approximation. It does **not** prove raw-image Gemma inference or Airplane Mode operation on the phone.

## Exact model

- `litert-community/gemma-4-E4B-it-litert-lm`
- Revision `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact `gemma-4-E4B-it.litertlm`
- 3,659,530,240 bytes
- SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- LiteRT-LM `f73637c57f0940b53da184e0d5adfc52a4e55eef`

The model lives under ignored `work/models/` and is never committed or uploaded.

## Current source of truth

- `../README.md` — Kaggle-facing architecture, reproducibility, and exact claim boundary.
- `DEMO_RUNBOOK.md` — build, demo, synthetic physical harness, and unverified Airplane Mode steps.
- `TEST_RESULTS.md` — current regression matrix and reproduction commands.
- `EMBEDDED_GEMMA_RESULTS.md` — exact model/build/runtime evidence.
- `DEVICE_INFERENCE_REPORT.md` — physical-only boundary.
- `outputs/demo-screens/README.md` — sanitized synthetic UI evidence.

## Try the phone flow safely

Use a bundled synthetic fixture or a publicly licensed non-patient image, wait for the local draft, and review every field. On the physical iPhone, Bristol/form/color are low-confidence hackathon suggestions derived from the local coarse map and organized by embedded Gemma; the review gate is required before Save.

Prototype only — not medical advice.
