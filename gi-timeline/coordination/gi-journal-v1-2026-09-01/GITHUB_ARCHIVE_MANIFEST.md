# Pre-change GitHub archive manifest

Date: 2026-09-01

Status: `PENDING_REMOTE_VERIFICATION`

The local checkout was clean at `f25f89a`, but that commit is not public-safe. It contains 55 downloaded wheels, one Mach-O build product, raw experimental evidence, and records bearing local paths. The local commit and tag are retained unchanged; neither may be pushed.

The public pre-change archive is therefore an orphan snapshot. Its source authority is `fed4a2db5cc59e9eea9ed75e83ee70ed31ce8cbc`. Product-lane app, package, and main-project source is preserved for the pre-change state; public-safety text neutralizations below explain the intentional differences from the private local checkout.

Included:

- App and provider-neutral source.
- Main Xcode project and shared Swift package.
- Unit, UI, persistence, PDF, lifecycle, and provider-contract tests.
- Deterministic test fixtures and app assets.
- Selected scripts that contain no user-specific path, signing team, UDID, or private credential marker.
- Selected release/privacy/support/licensing documents.
- LiteRT wrapper source and upstream checksum/license metadata, but no downloaded framework.
- Machine-readable state, task, and supporting-item ledgers.

Sanitized exceptions to byte identity:

- Historical release-plan and SBOM receipts were made location-neutral while retaining their hashes, counts, and evidence limits.
- Dependency reproduction commands now use workspace-relative scratch paths and the selected Xcode SDK rather than host-specific paths.
- The physical-Qwen runner now requires `QWEN3_SNAPSHOT_PATH`, `SOURCE_PACKAGES_DIR`, and `EVIDENCE_ROOT` instead of embedding host paths.
- The App Store validator now requires `EXPECTED_PHYSICAL_TEAM_ID` for the signed physical lane instead of embedding a Personal Team identifier.

Local pre-publish receipts:

- SwiftPM: 111/111 passed.
- Timeout contract: 4/4 passed.
- Resolution evidence contract: 14/14 passed.
- Self-contained Python schema tests: 9/9 passed.
- Complete historical Python prototype suite: 26 passed and seven failed because the intentionally excluded local virtual environment and model snapshot were absent.
- The generic App Store build compiled with signing disabled before the final archive commit existed; the fail-closed package validator still requires the final clean archive commit/tree binding.

Excluded or retained locally:

- Unpublished local Git history and the unsafe `f25f89a` archive commit/tag.
- Qwen/Gemma model payloads and downloaded runtimes.
- Wheels, built binaries, DerivedData, `.build`, `.xcresult`, archives, apps, IPAs, and process/device logs.
- Raw experimental image corpora pending publication-rights, metadata, and visual-provenance clearance.
- Local paths, account email, signing team IDs, device identifiers, provisioning records, and session/cache paths.

This snapshot does not claim Apple-native AI, device validation, TestFlight, App Store upload, clinical validation, or release readiness.
