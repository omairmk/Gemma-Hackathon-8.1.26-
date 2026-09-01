# GI Journal V1 manual-first release-lane status — 2026-09-01

## Outcome

`MANUAL_FIRST_LOCAL_CANDIDATE`

The isolated archive branch preserves a local-first, model-free public lane. AppStore-family configurations compile with `MANUAL_FALLBACK_RELEASE`; they select no model, package no model/runtime payload, and send photo attachments into the complete manual-entry route. Photos remain local, can be saved with the person's confirmed entry, and are available to selected-entry clinician PDFs.

The semantic implementation base is `05ed742aebcff601d328a919beb405ef0a9183d2` (tree `f09752a95a093c666ce90e75f0a38970398aa077`). The final content and seal commits are bound by the root `FINAL_SOURCE_SNAPSHOT_MANIFEST.json` rather than self-referential prose.

This is not a signed archive, TestFlight candidate, App Store submission, device result, or Apple-native AI success.

## Public product behavior confirmed locally

- `AppStore`, `AppStoreTesting`, and `PhysicalQualification` use the manual-fallback lane.
- The shipping target contains no linked or packaged LiteRT, CLiteRT, Gemma, Qwen, MLX, Apple classifier, `.litertlm`, `.safetensors`, `.gguf`, or `EmbeddedModels` payload.
- `ModelCatalog.normalFlowSelection` returns `nil` in `MANUAL_FALLBACK_RELEASE`.
- Attaching a photo retains it and enters manual review without model preparation or inference.
- Public copy states that this version does not analyze photos or prefill fields.
- Editable Yes / No / Not sure appearance answers, one final confirmation, save/edit/relaunch, and photo-inclusive PDF behavior remain covered.
- Historical provider-compatible source remains compile-isolated for internal continuity. This is not a claim that every legacy model name was erased from source strings.

## Current local evidence

Run from the repository root unless noted.

1. `swift test --package-path gi-timeline`
   - PASS: 111 tests, 0 failures.

2. App XCTest on the current AppStoreTesting host
   - PASS: 106 tests, 0 failures.
   - Covers persistence, person-confirmed appearance values, zero public inference calls, and photo-inclusive PDF content.

3. Unchanged public first-run/manual-route UI test
   - PASS: 1 test, 0 failures.
   - Covers first run, public accessibility audits, manual entry, save, edit, terminate, and relaunch.

4. Generic AppStoreTesting simulator build
   - PASS: `BUILD SUCCEEDED`.
   - Mach-O platform validation passed for iOS simulator arm64, minimum iOS 17.
   - Apple-framework-only package validation passed.
   - Uncompressed regular-file bytes: `24996305`; executable text segment: `3059712` bytes.

5. `gi-timeline/Scripts/TestAppStoreModelGateNegative.sh`
   - PASS: 10/10 deterministic payload-negative cases.

6. `gi-timeline/Scripts/ValidateLocalOnlySource.sh`
   - PASS: manual-fallback public lane, runtime dependency absent, zero remote package pins.

7. Resolved-package validation
   - PASS: zero remote pins, artifacts, or prebuilts; local `GITimelineCore` only.
   - Package lock SHA-256: `90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f`.

8. Provenance-pinned generic AppStore build with signing disabled
   - Compilation completed.
   - Source-checkout validation passed for all 152 files in the `gi-timeline/` scope at the exact semantic commit/tree.
   - The package gate then failed closed exactly because no owner-approved HTTPS privacy/support URLs were supplied.
   - This is an external release-input blocker, not a passing production build.

9. Independent shipping audit
   - CONFIRMED: no P0/P1 source regression.
   - P2 boundary: compatibility-only legacy types/strings remain; no linked, packaged, or invoked public runtime was found.

## Apple-native and synthetic decision

`APPLE_NATIVE_DIRECTIONAL_NO_GO`

Vision feature-print and one bounded tiny Create ML transition did not pass the complete directional gate. In particular, color failed and the tiny model produced no correct displayed `Yes` for red, black, or tar-like positives. The fresh image set was incomplete, duplicated, partly undecodable, and semantically out of scope. No Apple-native model was integrated. Exact metrics and hashes are in `APPLE_NATIVE_DIRECTIONAL_DECISION_2026-09-01.md`.

## External and owner-only blockers

- GitHub branch/tag publication is blocked by missing GitHub authentication in this execution surface. Local commits and tags remain intact.
- A full generic `AppStore` package pass requires approved live HTTPS privacy and support URLs; none were invented.
- Signed archive and TestFlight export require the correct signing identity, profile, team/account authority, and approved submission metadata.
- No physical iPhone qualification occurred: `UNVERIFIED-NO-DEVICE`.
- No upload, signing-account mutation, pricing decision, legal declaration, or App Store Connect action occurred.

## Cleanup status

Phase 5 is `NOT_STARTED_REMOTE_GATES_UNMET`. No authored evidence, model cache, worktree, or ambiguous local corpus was deleted. Eighteen generated Python bytecode files that contaminated a production source check were moved intact to an explicit local quarantine; that reversible build-input correction is recorded separately in the root cleanup manifest.

## Durable resume checkpoint

1. Verify the tagged parent-bound source manifest locally.
2. Restore GitHub authentication and push only the pre-change and final archive refs.
3. Verify both remote refs with `git ls-remote` and perform fresh remote-clone tests.
4. Supply approved public privacy/support URLs for a provenance-pinned production build.
5. Do not begin Phase 5 cleanup until both remote archives and required supporting evidence are verified.
