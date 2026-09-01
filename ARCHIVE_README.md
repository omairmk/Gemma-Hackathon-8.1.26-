# GI Journal pre-Apple-native source snapshot

This branch is the public, sanitized pre-change snapshot for the Apple-native GI Journal work that began on 2026-09-01.

The authoritative local source baseline is commit `fed4a2db5cc59e9eea9ed75e83ee70ed31ce8cbc` (tree `0fb19b1f3cbbabfc4887bd438799ec23efb36503`). The local checkout was later found at `f25f89aa54b220f4155c2eb6cf8c463579901a68`; that child commit changes archive/evidence files but not the app, test, package, or Xcode-project source selected for this snapshot.

The local `f25f89a` commit and its annotated tag remain intact, but are deliberately not ancestors of this branch. They contain host wheels, a built executable, raw experimental images, local paths, and device/signing history that must not become reachable through this public repository.

This archive is source-equivalent for the selected product lane, not a blind byte-for-byte publication of every local file. A small number of text-only archive neutralizations remove host-specific paths and identifiers from historical documents and scripts; the exact categories are listed in `gi-timeline/coordination/gi-journal-v1-2026-09-01/GITHUB_ARCHIVE_MANIFEST.md`.

## What this snapshot contains

- The current `GITimeline` app source, main Xcode project, shared package, unit tests, UI tests, and deterministic test fixtures.
- The provider-neutral inference and lifecycle code as it existed before Apple-native implementation.
- Selected build/evaluation scripts that passed the public-path scan after archive neutralization.
- LiteRT wrapper source, upstream provenance, license, and checksum pins needed to explain the pre-change dependency state; no downloaded framework or model payload is included.
- Selected public release, privacy, support, notice, and architecture documents.
- A machine-readable work ledger, observed-state receipt, archive manifest, and supporting-item classification.

## Evidence boundary

At this snapshot, the public App Store lane is manual-first. Apple-native photo suggestions are not yet integrated or qualified. Existing Qwen and Vision experiments remain synthetic, non-device evidence and do not establish product, clinical, TestFlight, signing, archive, or App Store readiness.

Raw synthetic experiment corpora and private/local evidence are represented by local hashes and classifications, not published here. Publication rights, embedded metadata, and visual provenance were not sufficiently verified for those files at the pre-change gate.

See `gi-timeline/coordination/gi-journal-v1-2026-09-01/` for exact scope and restore instructions.
