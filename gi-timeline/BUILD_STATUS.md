# Build-status record

This file records only commands actually attempted on July 31, 2026.

## Dependency milestone

- The v0.14.0 checksum failure was reproduced in an approved Xcode execution context. Exact output, four digests, primary sources, alternatives, and rollback are recorded in `DEPENDENCY_DECISION.md`.
- The project now pins the official exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`. It is the direct child of the `v0.14.0` tag and changes only the iOS/macOS binary checksums in `Package.swift`.
- Clean package resolution succeeds and `Package.resolved` contains exactly that revision. Checksum verification is not disabled.

## Observed checks

| Command/check | Result |
|---|---|
| `plutil -lint GITimeline.xcodeproj/project.pbxproj GITimeline/Info.plist` | PASS: both files `OK`. |
| `swift test --scratch-path .build/host-scratch` | PASS: 14 `GITimelineCore` tests, 0 failures. |
| `swiftc -parse` over app, app-test, package, and package-test Swift files | PASS. |
| Exact-revision `xcodebuild -resolvePackageDependencies` | PASS: resolved official LiteRT-LM `f73637c…`. |
| Clean project on local iPhone 17 Pro Max / iOS 26.5 simulator with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` | PASS: 11 app-target simulator tests, 0 failures; `** TEST SUCCEEDED **`. Coverage includes real in-memory SwiftData rollback fault points and visible deletion-error state, exact nil/manual display prose, ViewModel timeout/late-result locking, and missing/uninitializable-model importer recovery; it is still not the physical acceptance run. |
| Generic dual-architecture simulator test build | Non-qualifying x86_64 slice failed because the v0.14.0 iOS binary ships arm64 simulator code but no x86_64 slice; the arm64 build and tests passed. |

The passing clean project proves SwiftPM resolution and arm64 simulator compilation against the official v0.14 wrapper/binaries at the exact checksum-correction revision. It does **not** prove that a physical iPhone can launch the app, load a model, consume an image, or work offline.

No physical device build, signing check, model import, local Gemma inference, SwiftData device smoke, Airplane-Mode run, device file-protection log, device memory measurement, or five-run latency/stability gate was run. Xcode 26.6 (17F113) and Swift 6.3.3 are installed and the Xcode license is accepted.
