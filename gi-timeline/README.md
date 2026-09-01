# GI Journal

> **Current Build 8 boundary — 2026-08-04:** The milestone narrative below is historical and does not describe shipping V1. The current public product uses **Log / Journal / Settings**, embeds the full on-device Gemma model, has no treatment-change or Progress workflow, and creates photo-inclusive PDFs that fail closed if any expected attached photo cannot be verified. Use [`Release/APP_STORE_RELEASE_PLAN.md`](Release/APP_STORE_RELEASE_PLAN.md) and [`Release/SUBMISSION_PACKET_BUILD8_2026-08-03.md`](Release/SUBMISSION_PACKET_BUILD8_2026-08-03.md) as the active release boundary.

GI Journal is a private, local-first iPhone record for bowel movements. A person can log with or without a photo, review every photo-derived suggestion before saving, add symptoms and context themselves, mark entries for discussion, compare fixed seven-day periods around one treatment change, and export a clinician-readable PDF.

The Xcode project and internal module names remain `GITimeline` to preserve build and data continuity. The product-facing name is **GI Journal**.

## Milestone status

- The patient flow is now **Log / Journal / Progress**.
- Attaching a photo starts analysis automatically. Suggestions remain visibly unconfirmed until the person reviews photo usability, Bristol stool type, and mixed form.
- A photo-analysis failure, cancellation, or timeout retains the photo and draft and immediately opens manual entry. A late result from the revoked attempt is ignored.
- No-photo entries, daily completeness, treatment markers, discussion marks, fixed seven-day comparisons with the full required metric/denominator set and explicit partial-window labeling, and inclusive-range PDF export are implemented.
- The generated Letter PDF is searchable, repeats a compact header after page one, includes page footers and privacy language, and deletes its temporary copy after preview/share/cancel/failure.
- Ordinary arm64 **Release** builds model-free, displays as GI Journal, and currently produces a 44 MB simulator app bundle.
- Automated evidence currently passes: 38 core tests, 65 app tests, and 5 end-to-end UI tests.

## Model and evidence boundary

The optional Hackathon configuration retains the pinned `litert-community/gemma-4-E4B-it-litert-lm` artifact and LiteRT-LM integration. The model is ignored from Git and is not included in ordinary Release.

The pinned physical raw-image path now executes in an isolated synthetic harness: brown passed alone, and brown plus green produced distinct strict observations in a launch-only suite. That suite still failed 2/3 because the non-target control returned `BROWN` instead of `OTHER`; a fresh-process control-only run repeated the same false positive. A separate local pixel-map-to-text bridge also has physical engineering evidence, but Gemma does **not** receive the raw photo on that route. Its synthetic labels are not clinical ground truth, and the candidate did not replace the baseline after bounded holdout runs stalled.

Do not interpret isolated raw-image execution, successful build/install/launch, Simulator inference, or the disclosed bridge as 3/3 physical raw acceptance or proof of the ordinary review/save flow. Real-photo accuracy and clinical validity are not established. See `DEVICE_INFERENCE_REPORT.md` and `PHOTO_SUGGESTION_EVALUATION.md` for the route-separated ledger.

## Build

Open `GITimeline.xcodeproj`, select the `GITimeline` scheme, and build the normal Release configuration for a model-free app. Use the Hackathon configuration only when the exact pinned model is available locally and the build-time verification script succeeds.

## Milestone evidence

- `GI_JOURNAL_MILESTONE_HANDOFF.md` — implementation, acceptance matrix, demo script, and remaining gates.
- `PHOTO_SUGGESTION_EVALUATION.md` — frozen synthetic holdout protocol and route-separated results.
- `DEVICE_INFERENCE_REPORT.md` — physical-device evidence and blockers.
- `outputs/gi-journal-milestone/` — synthetic PDF and visual evidence.

Prototype only. GI Journal does not diagnose, triage, recommend treatment, or replace medical care.
