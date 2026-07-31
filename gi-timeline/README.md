# GITimeline

Native SwiftUI + SwiftData starter candidate for a private local-inference GI Timeline demo. On-device and offline behavior remain unverified. The project is intentionally double-gated: organizer starter-code permission and a complete physical-device preflight must both be recorded in `MOBILE_PRECHECK.md` before `STATUS: GO` is earned.

## What is pinned

- Official LiteRT-LM Swift package: `v0.14.0`, commit `80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6`.
- Official source/sample reference: the ignored `Vendor/LiteRT-LM` checkout at the same detached commit; `samples/ios_and_mac/ContentView.swift` is the API/sample base adapted by `InferenceService.swift`.
- Xcode pin: `GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Verified on this Mac

```sh
swift test --scratch-path .build/host-scratch
```

Fourteen platform-neutral parser, contract, full four-flag safety truth-table, immutable-draft, reset, and async-lock tests pass. In a non-committed arm64 simulator overlay that changes only the stale upstream binary checksums to the current official release-asset digests, the app and its test target build and all eleven app-target simulator tests pass. Those tests now fault the real in-memory SwiftData transaction after insert/delete, surface the deletion-error state, verify exact nil/manual display prose, cover ViewModel timeout/late-result locking, and prove a missing or uninitializable model does not strand the model importer; they do not replace the physical acceptance run.

The committed exact remote package pin does not presently resolve: the v0.14.0 tag manifest's binary checksums differ from the current assets served by the same official release. `BUILD_STATUS.md` records the four exact digests and the qualifying limits. No workaround is committed because pinning a later correction commit would violate the frozen exact-tag requirement without explicit authorization.

## Physical preflight

1. Confirm organizer permission and record `STARTER_CODE_ALLOWED` without inference.
2. Resolve the upstream checksum decision, then open `GITimeline.xcodeproj`; select the physical iPhone and signing team without changing the bundle ID.
3. Build the app and run its test target on the phone.
4. Stage the exact E4B artifact in Finder-visible `Documents/Import/`; use the in-app importer with the preflight-recorded SHA-256. The source remains until the copied `model.tmp` hash matches, then it is atomically promoted. Import refuses unless at least twice the model size is free.
5. Complete every blank value in `MOBILE_PRECHECK.md`. Brown/green props in `Fixtures/` are synthetic and watermarked; they are for the required vision-contrast gate only.

No app-owned networking or analytics path is included. The stored privacy text is: “The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings.”
