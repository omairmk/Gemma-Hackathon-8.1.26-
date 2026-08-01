# Build-status record

## 2026-08-01 overnight supersession

The older 23-test and Developer-Mode-disabled rows below are retained as historical observations from their recorded times. Later current-source results are: exact Gemma 4 E4B real image smoke and normal-flow/relaunch **PASS** in the arm64 iPhone Simulator; host **14/14 PASS** at 00:24:25 EDT; arm64 app **31/31 PASS** at 00:24:41 EDT; smaller-device deterministic UI baseline **1/1 PASS** at 00:06:02 EDT; smaller-device dark plus Accessibility Extra Large **1/1 PASS** at 00:08:04 EDT; six screenshots visually inspected; and final current-source arm64 Release build **PASS** at 00:23:40 EDT. Developer Mode is now enabled. Physical Debug build/install is still **BLOCKED** because the project Debug development team is blank; offline iPhone proof remains `NOT_RUN`. See `OVERNIGHT_STATUS.md`, `TEST_RESULTS.md`, and `MORNING_HANDOFF.md`. Legacy device/end-to-end statuses are unchanged.

The historical sections below record only commands attempted on July 31, 2026; the supersession above records the final overnight August 1 checks.

## Dependency milestone

- The v0.14.0 checksum failure was reproduced in an approved Xcode execution context. Exact output, four digests, primary sources, alternatives, and rollback are recorded in `DEPENDENCY_DECISION.md`.
- The project now pins the official exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`. It is the direct child of the `v0.14.0` tag and changes only the iOS/macOS binary checksums in `Package.swift`.
- Clean package resolution succeeds and `Package.resolved` contains exactly that revision. Checksum verification is not disabled.

## Observed checks

| Command/check | Result |
|---|---|
| `plutil -lint GITimeline.xcodeproj/project.pbxproj GITimeline/Info.plist` | PASS: both files `OK`. |
| `swift test` | PASS on the current source at 2026-07-31 17:00 ET: 14 `GITimelineCore` tests, 0 failures. |
| `swiftc -parse` over app, app-test, package, and package-test Swift files | PASS. |
| Exact-revision `xcodebuild -resolvePackageDependencies` | PASS: resolved official LiteRT-LM `f73637c…`. |
| First post-audit arm64 simulator test attempt | BUILD FAILED before tests at 2026-07-31 15:37 ET: the new coordinator receipt accessor lacked an explicit `return`; no test executed. The one-line compile issue was corrected. |
| Current-source arm64 iPhone 17 Pro Max simulator tests | PASS at 2026-07-31 17:00 ET: 23 app-target tests, 0 failures, 0 skipped. |
| Isolated Debug simulator build | PASS: bundle ID `com.omairmkhan.GITimeline.debug`, display name `GI Timeline Lab`; contains the DEBUG-only lab, three synthetic fixtures, and probe path. |
| Debug simulator install and launch | PASS at 2026-07-31 17:00 ET on the arm64 iPhone 17 Pro Max simulator. The first launch exposed a missing framework runpath and the next exposed an inapplicable simulator file-protection assertion; both were corrected without weakening the physical-device assertion. The final app remained open at `New Entry` with model preparation required. |
| Fresh Release simulator build and inspection | PASS at 2026-07-31 17:00 ET: unchanged bundle ID `com.omairmkhan.GITimeline`, display name `GI Timeline`; embedded `CLiteRTLM.framework` and `@executable_path/Frameworks` runpath are present; no fixture files, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings were found in the built Release app. |
| Generic dual-architecture simulator test build | Non-qualifying x86_64 slice failed because the v0.14.0 iOS binary ships arm64 simulator code but no x86_64 slice; the arm64 build and tests passed. |
| Read-only physical discovery | PASS at 2026-07-31 16:15 ET: one wired, paired, booted iPhone 17 Pro Max (`iPhone18,2`), iOS `26.5.2 (23F84)`, connected CoreDevice tunnel; identifier redacted. Xcode lists it as an arm64 iOS destination. |
| Exact production/debug installed-bundle queries | BLOCKED before results: CoreDevice returned error `10005`, Developer Mode disabled. Installed state remains UNKNOWN; no build, signing change, or install was attempted. |

The passing clean project proves SwiftPM resolution and arm64 simulator compilation against the official v0.14 wrapper/binaries at the exact checksum-correction revision. It does **not** prove that a physical iPhone can launch the app, load a model, consume an image, or work offline.

## Prepared inference boundary

- `SELECTED_MODEL.json` is intentionally absent. No model is physically accepted or selected.
- First planned baseline only: `google/gemma-3n-E2B-it-litert-lm`, artifact `gemma-3n-E2B-it-int4.litertlm`, immutable revision `73b019b63436d346f68dd9c1dbfd117eb264d888`, expected bytes `3,388,604,416`, trusted SHA-256 `6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5`. The artifact is absent and no download occurred. The official page was opened for the owner, but Hugging Face authentication and owner acceptance of Google's Gemma terms remain incomplete.
- Compiled configuration only: LiteRT-LM `f73637c57f0940b53da184e0d5adfc52a4e55eef`; backend `.gpu`; vision `.cpu()`; `maxNumTokens=2048`; `topK=1`; `topP=1`; temperature `0`; seed `0`; prompt `gi-observation-v1`; `Message(contents: [.imageFile(path), .text(prompt)])`.

No physical device build, signing check, model import, local Gemma inference, SwiftData device smoke, Airplane-Mode run, device file-protection log, device memory measurement, or five-run latency/stability gate was run. Xcode 26.6 (17F113) and Swift 6.3.3 are installed and the Xcode license is accepted.

The sole next operator action is to open **Settings → Privacy & Security → Developer Mode** on the iPhone, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen and stop. This authorizes only repeated read-only readiness and installed-bundle discovery.
