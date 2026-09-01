# GI Journal public App Store release plan

Status: **manual-first candidate, not submitted, not Apple-processed**.
Updated: 2026-09-01.

This document is the current public-release authority for the Apple-native/manual-fallback branch. Older Build 6/8, Gemma, Qwen, LiteRT, MLX, raw-photo, physical-qualification, and synthetic-evaluation ledgers are retained only as historical or internal evidence. They do not describe the current public AppStore bundle and must not be copied into App Review, store metadata, support, or privacy claims.

## Current public promise

GI Journal is a local-first iPhone documentation app. Pricing and distribution remain an account-holder decision. The public build supports:

- Log, Journal, and Settings.
- Manual bowel-movement entries with or without an attached photo.
- Dated no-bowel-movement records.
- Editable saved entries and discussion bookmarks.
- One final confirmation before saving a visible entry.
- Photo-inclusive, date-bounded PDF export initiated by the person.
- Local storage with requested backup exclusion for the live journal, subject to iOS behavior.

The public build does **not** analyze photos, prefill fields from photos, include a generative model, include LiteRT/Gemma/Qwen/MLX runtime payloads, use remote inference, sync a journal, operate a developer journal server, or train on journal data.

GI Journal is a documentation tool for people working with an established care team. It must not claim to diagnose, triage, identify a cause/pathogen, assess clinical severity, reassure, or recommend treatment.

## Build-channel contract

| Channel | Current role | Shipping status |
|---|---|---:|
| Debug | Development and internal fixtures | Nonshipping |
| Hackathon | Historical/demo configuration only | Nonshipping |
| Release | Local model-free fallback control under the internal bundle ID | Nonshipping |
| AppStoreTesting | Public compilation conditions, non-production bundle ID, simulator/test evidence | Nonshipping |
| AppStore | Production bundle ID, public manual-fallback behavior, no retired AI runtime/model payload | Candidate only after signing, URLs, archive/IPA, physical, legal, privacy, and account gates pass |
| PhysicalQualification | No longer model-bound in this branch; it compiles the same reviewed manual-fallback source lane | Nonshipping/device-check lane only |

## Current local evidence

The 2026-09-01 isolated final branch has passed these non-device checks:

- Swift package tests: **111/111 PASS**.
- AppStoreTesting generic iOS Simulator build: **BUILD SUCCEEDED**.
- AppStoreTesting package validator: **PASS** with no retired AI runtime/model payload and `24,996,417` regular-file bytes.
- Manual-fallback payload negative cases: **10/10 PASS**.
- Resolved-source-package validator: **PASS** with zero remote pins, zero artifacts, zero prebuilts, and one local `GITimelineCore` dependency.
- Project syntax/listing: `plutil` and `xcodebuild -list` PASS.

This is source/simulator evidence only. It is not a signed production archive, exported IPA, TestFlight upload, Apple-processed size receipt, physical-device run, restart-after-unlock proof, in-place-update proof, accessibility proof, privacy/network observation, or legal/account approval.

## Required release gates

Before public submission, complete all of the following against one frozen source commit:

1. Replace the public HTTPS privacy/support URL placeholders with approved live URLs.
2. Build the production `AppStore` configuration with Apple Distribution signing.
3. Validate the signed `.xcarchive` using `Scripts/ValidateDevelopmentSignedAppStoreArchive.sh`.
4. Export the App Store/TestFlight `.ipa` and validate it using `Scripts/ValidateExportedAppStoreIPA.sh`.
5. Prove the exact signed archive and exported IPA contain no `.litertlm`, `.safetensors`, `.gguf`, `EmbeddedModels`, LiteRT, Gemma, Qwen, or MLX payload.
6. Run clean core/app/UI gates from a clean DerivedData location.
7. Run physical-device qualification for manual entry, optional photo attachment without analysis, save/relaunch, edit, no-bowel-movement records, PDF, Airplane Mode, restart-after-unlock, signed in-place update, VoiceOver, Dynamic Type, latency, memory, thermal, and storage-pressure behavior.
8. Perform an instrumented network/privacy observation against the exact installed build.
9. Obtain legal/account-holder approval for medical-intended-use wording, regulated-medical-device declarations, privacy answers, DSA/trader status, pricing, screenshots, support, and App Review notes.
10. Upload only after the exact artifact and metadata are approved by the account holder.

## AI/suggestion admission rule

The current public AppStore lane is manual-first. Any future AI-enabled branch must use a separate admission packet with provider-neutral wording, independent development and untouched validation sets, physical-device qualification, current license/notice review, privacy/support/metadata reconciliation, and fresh legal/account-holder approval. Synthetic or simulator evidence cannot by itself promote AI suggestions into the public build.

## Stop-ship conditions

Do not submit if any of the following is true:

- Public copy says or implies that the current build analyzes photos.
- A retired AI runtime/model payload is linked, embedded, copied, or present in the archive/IPA.
- Public URLs, privacy answers, support route, legal identity, price/territory choices, or regulated-device declarations are unresolved.
- Any required physical, accessibility, retention, PDF, privacy/network, archive, IPA, or upload gate is missing or failed.
- App Review or user-facing language claims clinical accuracy, diagnosis, triage, treatment, cause/pathogen identification, or reassurance.
