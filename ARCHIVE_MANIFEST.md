# Final archive manifest

Date: 2026-09-01

Status: `LOCAL_SEAL_PENDING_REMOTE_VERIFICATION`

Final branch: `archive/2026-09-01-apple-native-v1`

Truthful final tag: `gi-journal-manual-fallback-v1-2026-09-01`

The branch name records the mission that produced this archive. The tag records the actual product outcome: the Apple-native experiments failed the complete directional gate, no classifier was integrated, and the preserved public lane is manual-first.

## Commit structure

- Pre-change archive: branch `archive/2026-09-01-pre-apple-native`, commit `58420f66582a17e1d90540122bcb5a3d4c37c827`, tree `b070cfdf6416579987d6992215298213543b6735`, intended tag `gi-journal-pre-apple-native-2026-09-01`.
- Shipping-runtime removal: `726fa246eccca17fc74cda550343641401b9a394`.
- Accessibility repair and semantic implementation base: `05ed742aebcff601d328a919beb405ef0a9183d2`.
- Final content commit: recorded as `source_commit` in `FINAL_SOURCE_SNAPSHOT_MANIFEST.json`.
- Seal commit: the final tag target; it has the content commit as its only parent and adds only `FINAL_SOURCE_SNAPSHOT_MANIFEST.json`.

The earlier local tag `archive-2026-09-01-manual-fallback-726fa24` points to an intermediate, pre-accessibility-review commit. It is preserved as history but is not the final archive tag. The local `archive-2026-09-01-apple-native-v1-f25f89a` tag points to private/unsafe evidence history and must not be pushed.

## Included in Git

- GI Journal Swift source, Xcode project/schemes, local Swift package, tests, deterministic fixtures, and public app assets.
- Manual-fallback shipping configuration and payload/source validators.
- Save, persistence, lifecycle, appearance-contract, PDF, and UI/accessibility tests.
- Release, privacy, support, notice, intended-use, decision, and archive documentation.
- Pre-change archive receipts, task ledger, and supporting-item classification.
- Final Git-object manifest generator and verifier.

## Excluded or retained locally

- Qwen/Gemma model weights, LiteRT downloaded frameworks, MLX/Python runtime caches, wheels, and compiled executables.
- Raw Apple-native/Qwen experimental images and the incomplete fresh synthetic set.
- Local xcresults, DerivedData, `.build`, device/process/signing logs, apps, archives, and IPAs.
- Private local history reachable from `f25f89a` but not from either public archive branch.
- Ambiguous mixed-content release folders and active/dirty/unique worktrees.

Every relevant group is assigned one of `INCLUDED_IN_GIT`, `EXCLUDED_REPRODUCIBLE`, or `RETAIN_LOCAL_PENDING_CLARIFICATION` in `gi-timeline/coordination/gi-journal-v1-2026-09-01/SUPPORTING_ITEM_CLASSIFICATION.json`.

## Local evidence

- SwiftPM: 111/111 passed.
- App XCTest: 106/106 passed.
- Public manual-route UI/accessibility test: 1/1 passed.
- Generic AppStoreTesting build and Apple-framework-only package validation: passed.
- Payload-negative gate: 10/10 passed.
- Local-only source and resolved-package gates: passed.
- Provenance-pinned AppStore compile/source verification: passed through the deliberate owner-approved URL gate, then stopped.
- Independent shipping audit: no P0/P1 source regression.
- Apple-native directional gate: failed; no model integrated.
- Physical device, signing, archive export, TestFlight, and App Store processing: unverified/not performed.

## Remote and cleanup status

Both archive branch/tag pairs are locally preserved, but GitHub authentication was unavailable. No remote branch/tag or fresh remote-clone result is claimed. Phase 5 cleanup remains `NOT_STARTED_REMOTE_GATES_UNMET`.

## Integrity

`FINAL_SOURCE_SNAPSHOT_MANIFEST.json` is generated from immutable Git blobs in the final content commit. `gi-timeline/Scripts/VerifyFinalSourceSnapshotManifest.py` loads the manifest from the supplied seal ref, validates the one-parent/one-file seal contract, and hashes every content blob through Git rather than trusting the working tree.
