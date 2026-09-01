# GI Journal V1 manual-first archive

Status: `LOCAL_ARCHIVE_CANDIDATE_REMOTE_UNVERIFIED`

This branch preserves the narrow GI Journal V1 as a local-first, model-free public lane. A person can attach and retain a photo, complete or edit the journal fields, confirm the visible entry once, save and reopen entries, and export a clinician-readable PDF containing the selected entry's original photo.

The `AppStore`, `AppStoreTesting`, and `PhysicalQualification` configurations use `MANUAL_FALLBACK_RELEASE`. They do not select, link, load, or package Qwen, Gemma, LiteRT, MLX, an Apple classifier, or another model. Historical provider-compatible source remains for internal research continuity, but the intended public route does not invoke it.

## Why this is manual-first

Two bounded Apple-native experiments were completed before the archive was sealed:

- Vision feature-print references missed the complete directional utility gate.
- One tiny Create ML transition passed subject, Bristol, useful-suggestion, and aggregate correct-versus-wrong gates, but failed broad color and all positive red/black/tar display gates.

The fresh synthetic-image attempt was also unsuitable for scoring or publication. No Apple-native classifier was integrated. Exact metrics and immutable local evidence hashes are recorded in `gi-timeline/Release/APPLE_NATIVE_DIRECTIONAL_DECISION_2026-09-01.md`.

## Evidence boundary

Confirmed locally:

- SwiftPM: 111 tests passed.
- App XCTest: 106 tests passed.
- The unchanged public first-run/manual-route UI test, including accessibility audits, save, edit, terminate, and relaunch: 1 test passed.
- Generic AppStoreTesting package build and Apple-framework-only payload validation passed.
- A provenance-pinned generic AppStore build compiled and verified its clean source checkout, then stopped at the intentional requirement for owner-approved public privacy and support URLs.
- Independent review found no P0/P1 shipping-source regression.

Not confirmed:

- No physical-device qualification, signing, archive export, TestFlight upload, Apple processing, or App Store submission occurred.
- Neither archive branch/tag has been verified on GitHub because repository authentication was unavailable.
- Phase 5 cleanup did not begin because both remote archive gates are unmet.

This archive is not an Apple-native AI success, clinical validation, device result, TestFlight candidate, or App Store release receipt.

## Archive structure

- `ARCHIVE_MANIFEST.md` — final scope, evidence, exclusions, and status.
- `FINAL_SOURCE_SNAPSHOT_MANIFEST.json` — immutable Git-object manifest added by the seal commit.
- `RESTORE.md` — restore and verification commands.
- `CLEANUP_MANIFEST.json` — fail-closed cleanup status and retained groups.
- `gi-timeline/coordination/gi-journal-v1-2026-09-01/` — pre-change archive records, work ledger, and supporting-item classification.

The parent-bound seal intentionally separates content from its manifest: the tagged seal commit adds only `FINAL_SOURCE_SNAPSHOT_MANIFEST.json`; that manifest hashes every tracked blob in the content parent. Verify it with `gi-timeline/Scripts/VerifyFinalSourceSnapshotManifest.py`.
