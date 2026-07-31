# Build-status record

This file records only commands actually attempted on July 31, 2026.

## Frozen project state

- The committed Xcode project remains pinned to the official LiteRT-LM `v0.14.0` tag, commit `80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6`, with the remote package reference and `Package.resolved` intact.
- Official resolution currently fails before compilation because that tag's `Package.swift` declares iOS checksum `4a4bdb0e89689ceacc54c2fb7ae0efe8f5dad2404110976a29c3bf6b374a511e`, while the current official v0.14.0 release asset and GitHub release API both report `dddac2f6713ed65eaf01c18e115d9fec22184adf575cc7856a21387e8ba937e1`.
- The analogous macOS values are tag-declared `13e818c9d3987afa87f0716884ebf0b6b10677b480717b8b098146e6b4f45847` versus current release-asset `450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7`.
- No workaround or dependency deviation is committed. A later upstream commit updates these checksums, but using it would depart from the frozen exact-tag contract and requires an explicit decision.

## Observed checks

| Command/check | Result |
|---|---|
| `plutil -lint GITimeline.xcodeproj/project.pbxproj GITimeline/Info.plist` | PASS: both files `OK`. |
| `swift test --scratch-path .build/host-scratch` | PASS: 14 `GITimelineCore` tests, 0 failures. |
| `swiftc -parse` over app, app-test, package, and package-test Swift files | PASS. |
| Exact remote `xcodebuild -resolvePackageDependencies` | BLOCKED: exit 74 at the upstream v0.14.0 binary checksum mismatch described above. |
| Non-qualifying temporary overlay: exact v0.14.0 source with only the two checksums changed to the current official release-asset digests; app package reference changed only in `/private/tmp` to that local source; arm64 simulator `build-for-testing` | PASS: `** TEST BUILD SUCCEEDED **`. The frozen project itself was not altered. |
| Same temporary overlay on the local iPhone 17 Pro / iOS 26.5 simulator, arm64 only | PASS: 11 app-target simulator tests, 0 failures; `** TEST SUCCEEDED **`. Coverage includes real in-memory SwiftData rollback fault points and visible deletion-error state, exact nil/manual display prose, ViewModel timeout/late-result locking, and missing/uninitializable-model importer recovery; it is still not the physical acceptance run. |
| Generic dual-architecture simulator test build | Non-qualifying x86_64 slice failed because the v0.14.0 iOS binary ships arm64 simulator code but no x86_64 slice; the arm64 build and tests passed. |

The passing overlay proves the current application and test sources compile and execute against the exact v0.14.0 source/API when the official release-asset checksums are used. It does **not** prove that the committed exact remote pin resolves, that a physical iPhone can load E4B, or that any mobile preflight gate passed.

No physical device build, signing check, model import, local Gemma inference, SwiftData device smoke, Airplane-Mode run, device file-protection log, device memory measurement, or five-run latency/stability gate was run. Xcode 26.6 (17F113) and Swift 6.3.3 are installed and the Xcode license is accepted.
