# GI Journal V1 release-lane status — 2026-09-01

## Outcome

`MANUAL_FIRST_LOCAL_CANDIDATE`

This isolated branch preserves the current working journal as a local-first, model-free public lane. The App Store configurations compile with `MANUAL_FALLBACK_RELEASE`; they select no model, package no model/runtime payload, and send attached photos directly into the complete manual-entry path. Photos remain local, are saved with confirmed entries when the person chooses to save, and remain available for photo-inclusive clinician PDFs.

This is not a TestFlight or App Store submission receipt. No upload, signing-account mutation, device install, Apple processing, pricing, privacy URL, or support URL decision was performed.

## Branch and checkout boundary

- Worktree: `/private/tmp/gi-final-20260901`
- App root: `/private/tmp/gi-final-20260901/gi-timeline`
- Branch: `archive/2026-09-01-apple-native-v1`
- Starting HEAD for this release-lane pass: `58420f66582a17e1d90540122bcb5a3d4c37c827`
- Canonical checkout preserved read-only during this pass: `/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi`

## Product behavior now asserted locally

- AppStore, AppStoreTesting, and PhysicalQualification configurations are manual-fallback public lanes.
- The public app contains no LiteRT, CLiteRT, Gemma, Qwen, MLX, `.litertlm`, `.safetensors`, `.gguf`, or `EmbeddedModels` payload.
- `ModelCatalog.normalFlowSelection` returns `nil` in `MANUAL_FALLBACK_RELEASE`.
- The no-LiteRT compile path keeps historical coordinator call sites fail-closed through `UnavailableInferenceService` / missing-model errors rather than linking a retired runtime.
- Public copy says this version contains no model and does not analyze photos or prefill fields.
- Historical AI suggestion/provenance code remains source-compatible for internal AI-enabled builds, but the public/manual lane does not invoke it.

## Local evidence

Run from `/private/tmp/gi-final-20260901/gi-timeline` unless otherwise noted.

1. `swift test`
   - PASS: 111 tests, 0 failures.
   - Includes the current appearance-suggestion contract tests for Yes / No / Not sure wording and negative red/black/tarry suggestions.

2. `xcodebuild test -project gi-timeline/GITimeline.xcodeproj -scheme 'GITimeline App Store' -configuration AppStoreTesting -destination 'platform=iOS Simulator,id=064ED559-F342-4A64-8626-4561899BA0B1' -derivedDataPath /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-timeline/DerivedData-Release -only-testing:GITimelineTests CODE_SIGNING_ALLOWED=NO`
   - PASS: 106 XCTest cases, 0 failures.
   - Confirms the model-free AppStoreTesting host compiles and runs the app-unit suite.

3. `xcodebuild -project gi-timeline/GITimeline.xcodeproj -scheme 'GITimeline App Store' -configuration AppStoreTesting -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/gi-appstoretesting-dd.JjyXw7 CODE_SIGNING_ALLOWED=NO build`
   - PASS: `** BUILD SUCCEEDED **`.
   - App validator output: `MACHO_PLATFORM_VALIDATION: PASS platform=7 minimum=17.0.0 arch=arm64`.
   - App validator output: `validated Apple-framework-only AppStore package; uncompressed_regular_file_bytes=24993793; safety_margin_bytes=725006207; app_text_segment_bytes=3059712`.

4. `Scripts/TestAppStoreModelGateNegative.sh`
   - PASS: 10/10 deterministic payload-gate cases.

5. `Scripts/ValidateResolvedSourcePackages.sh /private/tmp/gi-appstoretesting-dd.JjyXw7/SourcePackages`
   - PASS.
   - `package_resolved_sha256=90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f`
   - `remote_pins=0 artifacts=0 prebuilts=0 local_dependency=GITimelineCore runtime_payload=absent`

6. `Scripts/ValidateLocalOnlySource.sh`
   - PASS.
   - `public_lane=manual_fallback runtime_dependency=absent remote_package_pins=0 configurations=AppStore,AppStoreTesting,PhysicalQualification`

7. `plutil -lint GITimeline.xcodeproj/project.pbxproj && xcodebuild -project GITimeline.xcodeproj -list`
   - PASS.
   - Xcode package graph resolves only the local `GITimelineCore` package.

8. Script syntax checks:
   - `zsh -n Scripts/ValidateAppStoreBuild.sh`
   - `zsh -n Scripts/ValidateDevelopmentSignedAppStoreArchive.sh`
   - `zsh -n Scripts/ValidateExportedAppStoreIPA.sh`
   - `zsh -n Scripts/ValidateResolvedSourcePackages.sh`
   - `zsh -n Scripts/TestAppStoreModelGateNegative.sh`
   - `python3 -m py_compile Scripts/CompareNormalizedAppPayloadFiles.py`
   - PASS.

## AI and synthetic-image lane

The Apple-native/synthetic lane is not eligible to freeze or score from the current fresh fixture directory:

- Fixture root: `/private/tmp/gi-apple-native-synthetic-20260901`
- `batch-c/C05.png` is missing.
- `batch-c/C06.png` and `batch-c/C07.png` are zero-byte files.
- `batch-c/test-stream.png` is a 5-byte invalid byproduct.
- Exact SHA-256 duplicates:
  - `batch-a/A02.png` = `batch-c/C02.png`
  - `batch-a/A03.png` = `batch-b/B02.png`
  - `batch-a/A05.png` = `batch-b/B06.png`
  - `batch-a/A06.png` = `batch-b/B04.png`
  - `batch-c/C06.png` = `batch-c/C07.png` = empty file SHA

Prior Apple-native/Qwen-style synthetic attempts remain non-release evidence only. This branch therefore preserves the working manual-first release lane rather than claiming a useful on-device AI candidate.

## External or owner-only blockers

- GitHub preservation push is blocked by local GitHub authentication: the post-candidate push attempt failed with `fatal: could not read Username for 'https://github.com': Device not configured`, and `gh` is unavailable in this shell.
- App Store/TestFlight archive and upload require approved Apple signing/account authority.
- Public production App Store build requires real approved privacy/support URLs. This branch intentionally does not invent them.
- Physical-device behavior is unverified; no iPhone install or TestFlight processing occurred.

## Durable resume checkpoint

Resume from:

```bash
cd /private/tmp/gi-final-20260901/gi-timeline
git status --short --branch
swift test
Scripts/ValidateLocalOnlySource.sh
Scripts/TestAppStoreModelGateNegative.sh
```

If GitHub authentication is restored, preserve this branch before any cleanup:

```bash
cd /private/tmp/gi-final-20260901
git push origin archive/2026-09-01-apple-native-v1
```

Do not clean, delete, or overwrite authored evidence until the remote archive branch/tag has been verified.
