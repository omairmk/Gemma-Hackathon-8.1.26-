# GITimeline

Native SwiftUI + SwiftData starter candidate for a private local-inference GI Timeline demo. On-device and offline behavior remain unverified. Private physical-device experiments are independent of organizer starter-code permission; event use remains blocked until that answer is recorded.

> **2026-08-01 overnight POC supersession.** Later current-source evidence supersedes the historical 23-test, missing-model, planned-Gemma-3n, and Developer-Mode-disabled statements retained below. The exact Gemma 4 E4B artifact now passes real image inference and the normal save/History/relaunch path locally in the arm64 iPhone Simulator (`SIMULATOR_GEMMA_POC_GO`); final tests pass 14/14 host and 31/31 app, two deterministic UI configurations pass 1/1, six screens pass visual inspection, and the final arm64 Release build passes. Developer Mode is freshly enabled; the physical Debug build remains blocked only until the owner selects an Apple development team. Physical and offline iPhone inference remain unproven. See `MORNING_HANDOFF.md` and `TEST_RESULTS.md`. This POC note does not upgrade the legacy `DEVICE_INFERENCE_STATUS` or `APP_END_TO_END_STATUS` fields.

## What is pinned

- Official LiteRT-LM Swift package: exact official `release/v0.14` checksum-correction revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`, a direct child of the `v0.14.0` tag that changes only `Package.swift` checksums.
- Official source/sample reference: `v0.14.0` Swift wrapper and binaries; `samples/ios_and_mac/ContentView.swift` is the API/sample base adapted by `InferenceService.swift`.
- Xcode pin: `GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Verified on this Mac

```sh
swift test
```

Fourteen platform-neutral parser, contract, full four-flag safety truth-table, immutable-draft, reset, and async-lock tests passed at 2026-07-31 17:00 ET. The fresh current-source arm64 iPhone 17 Pro Max simulator run passed all twenty-three app-target tests with no failures or skips, and the Debug app installed, launched, and remained open at `New Entry`. Simulator evidence does not replace the physical acceptance run.

`DEPENDENCY_DECISION.md` records the reproduced v0.14.0 checksum failure, exact official correction provenance, release-asset sizes and hashes, alternatives, commands, and rollback plan. Checksum verification remains enabled.

## Build isolation and inference boundary

- Debug is isolated as `com.omairmkhan.GITimeline.debug` with display name `GI Timeline Lab`. Its synthetic fixtures, probe path, and lab UI are DEBUG-only.
- Release remains `com.omairmkhan.GITimeline` with display name `GI Timeline`. Fresh built-Release inspection found the embedded LiteRT-LM framework and required runtime search path, with no lab fixture files, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings.
- `SELECTED_MODEL.json` is intentionally absent. No model has earned physical gates or owner acceptance.
- The first planned baseline—not a selected model—is `google/gemma-3n-E2B-it-litert-lm` at immutable revision `73b019b63436d346f68dd9c1dbfd117eb264d888`, artifact `gemma-3n-E2B-it-int4.litertlm`, expected size `3,388,604,416` bytes, trusted SHA-256 `6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5`. No artifact bytes were downloaded.
- The compiled deterministic configuration is LiteRT-LM `f73637c57f0940b53da184e0d5adfc52a4e55eef`, `.gpu`, vision `.cpu()`, `maxNumTokens=2048`, `topK=1`, `topP=1`, temperature `0`, seed `0`, prompt `gi-observation-v1`, and `Message(contents: [.imageFile(path), .text(prompt)])`. It has not run on a physical phone.

## One next operator action

The intended phone is now visible as a wired, paired iPhone 17 Pro Max running iOS 26.5.2, and Xcode lists it as an arm64 iOS destination. Developer-app inspection stopped with `CoreDeviceError 10005` because Developer Mode is disabled; installed GI Timeline bundle state therefore remains unknown.

On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen, then stop. This authorizes only another read-only readiness and installed-bundle check.

No app-owned networking or analytics path is included. The stored privacy text is: “The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings.”
