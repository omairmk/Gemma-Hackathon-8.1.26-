# GITimeline

Native SwiftUI + SwiftData starter candidate for a private local-inference GI Timeline demo. On-device and offline behavior remain unverified. Private physical-device experiments are independent of organizer starter-code permission; event use remains blocked until that answer is recorded.

## What is pinned

- Official LiteRT-LM Swift package: exact official `release/v0.14` checksum-correction revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`, a direct child of the `v0.14.0` tag that changes only `Package.swift` checksums.
- Official source/sample reference: `v0.14.0` Swift wrapper and binaries; `samples/ios_and_mac/ContentView.swift` is the API/sample base adapted by `InferenceService.swift`.
- Xcode pin: `GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Verified on this Mac

```sh
swift test --scratch-path .build/host-scratch
```

Fourteen platform-neutral parser, contract, full four-flag safety truth-table, immutable-draft, reset, and async-lock tests pass. The clean project resolves the exact official correction revision, builds for the arm64 iPhone 17 Pro Max / iOS 26.5 simulator, and passes all eleven app-target tests. Those tests fault the real in-memory SwiftData transaction after insert/delete, surface the deletion-error state, verify exact nil/manual display prose, cover ViewModel timeout/late-result locking, and prove a missing or uninitializable model does not strand the model importer; they do not replace the physical acceptance run.

`DEPENDENCY_DECISION.md` records the reproduced v0.14.0 checksum failure, exact official correction provenance, release-asset sizes and hashes, alternatives, commands, and rollback plan. Checksum verification remains enabled.

## Physical preflight

1. Record organizer permission separately for event eligibility; it does not block private technical testing.
2. Open `GITimeline.xcodeproj`; select the physical iPhone and signing team without changing the Release bundle ID.
3. Build the app and run its test target on the phone.
4. After device-memory confirmation and explicit download approval, stage the exact descriptor-selected artifact in Finder-visible `Documents/Import/`; use the in-app importer with the trusted SHA-256. The first baseline is the Gallery-pinned image-capable Gemma 3n E2B unless a qualifying artifact is already present. Retain the staged source through imported-copy verification and engine initialization; deletion requires separate approval.
5. Complete every blank value in `MOBILE_PRECHECK.md`. Brown/green props in `Fixtures/` are synthetic and watermarked; they are for the required vision-contrast gate only.

No app-owned networking or analytics path is included. The stored privacy text is: “The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings.”
