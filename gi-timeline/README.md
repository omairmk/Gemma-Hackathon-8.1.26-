# GI Journal

GI Journal is a private, local-first iPhone record for bowel movements. The product-facing name is **GI Journal**; Xcode and module names remain `GITimeline` for build and data continuity.

## Current public lane

The archived V1 public lane is manual-first and model-free:

- A person can create an entry with or without a photo.
- An attached photo is retained locally and shown during review; this public lane does not analyze it or prefill fields.
- All visible fields, including red/blood-like and black/tar-like Yes / No / Not sure answers, remain editable.
- One final confirmation saves the currently displayed person-confirmed entry.
- Saved entries can be reopened and edited after relaunch.
- The selected-entry clinician PDF includes the original retained photo and final person-confirmed values.
- Failure-prone model preparation or inference cannot block the manual route because the public build selects no model.

The `AppStore`, `AppStoreTesting`, and `PhysicalQualification` configurations compile with `MANUAL_FALLBACK_RELEASE`. The shipping target has no Qwen, Gemma, LiteRT, MLX, Apple classifier, model payload, or remote runtime dependency. Historical provider-compatible types and research strings remain in source for internal continuity; they are not an active public runtime path.

## Apple-native decision

The bounded Vision feature-print and tiny Create ML experiments did not pass the complete directional gate, so no Apple-native classifier was integrated. See `Release/APPLE_NATIVE_DIRECTIONAL_DECISION_2026-09-01.md` for exact metrics and evidence hashes.

## Build and test

Open `GITimeline.xcodeproj` and select `GITimeline App Store`. `AppStoreTesting` is the locally executable unsigned test configuration. The production `AppStore` configuration deliberately requires an exact clean source commit/tree plus owner-approved HTTPS privacy and support URLs.

Core checks:

```bash
swift test
Scripts/ValidateLocalOnlySource.sh
Scripts/TestAppStoreModelGateNegative.sh
```

Release truth and remaining operator gates are in:

- `Release/APPLE_NATIVE_MANUAL_FALLBACK_STATUS_2026-09-01.md`
- `Release/APP_STORE_RELEASE_PLAN.md`
- `Release/APP_STORE_METADATA.md`

Prototype only. GI Journal is a documentation aid; it does not diagnose, triage, recommend treatment, identify pathogens, or replace medical care.
