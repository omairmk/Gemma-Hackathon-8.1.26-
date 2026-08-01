# GI Timeline test results

Updated: 2026-08-01 00:30 EDT (America/New_York)

## Current verdict

The final post-screenshot host and arm64 Simulator suites are green. Real Gemma smoke, the normal app path, deterministic UI automation, visual acceptance, and the current-source arm64 Release build all pass within their stated boundaries. The physical iPhone build remains blocked by signing-team selection, and offline iPhone proof was not run.

| Check | Result | Evidence/time |
|---|---|---|
| Host SwiftPM suite | **PASS: 14/14**, 0 failures | 2026-08-01 00:24:25 EDT |
| arm64 iPhone Simulator app suite | **PASS: 31/31**, 0 failures | 2026-08-01 00:24:41 EDT; qualifying result at `DerivedData/Logs/Test/Test-GITimeline-2026.08.01_00-24-36--0400.xcresult` |
| Debug arm64 Simulator build/install/launch | **PASS** | The exact Debug bundle executed the real smoke and normal-flow runners. |
| Real Gemma image smoke | **PASS** | `GEMMA_SMOKE_RESULTS.json`; summarized in `GEMMA_SMOKE_RESULTS.md` |
| Real-provider normal flow | **PASS** | `NORMAL_FLOW_REAL_GEMMA.json` and `NORMAL_FLOW_RELAUNCH.json` |
| Smaller-device deterministic UI baseline | **PASS: 1/1** in 50.854 s | Full-screen iPhone 17e Simulator, 390 x 844 points; 2026-08-01 00:06:02 EDT |
| Smaller-device dark/accessibility UI | **PASS: 1/1** in 75.595 s | Same device, dark mode and Accessibility Extra Large; 2026-08-01 00:08:04 EDT |
| Visual inspection and six screenshots | **PASS** | `01`-`05` are 1320 x 2868 px large-presentation captures; `06` is the 1170 x 2532 px / 390 x 844 pt smaller dark/accessibility capture. |
| Current-source arm64 Release build | **PASS** | 2026-08-01 00:23:40 EDT; `** BUILD SUCCEEDED **`; Release remains model-free. |
| Physical iPhone build/install | `BLOCKED` | Debug `DEVELOPMENT_TEAM` is blank. |
| Physical Airplane-Mode cold launch | `NOT_RUN` | Never observed. |

## Coverage represented by the 31 app tests

The current app suite includes the exact Gemma 4 E4B descriptor and DEBUG-only selection, `nil` Release selection, CPU Simulator configuration, import/receipt integrity, strict token and structured parsers, one-repair success, double-parse-failure manual save, retry with the same preserved draft, timeout/stale-attempt locking, failed-save rollback, reviewed provenance, exact Simulator CPU/location provenance, explicit JSON `null` persistence for nil Bristol type, immutable synthetic-demo reset safety, truthful provider attribution, readiness labels, deletion/reconciliation, sanitized image handling, fixture integrity, evidence redaction, and exclusive runtime coordination.

The 14 host tests cover the parser contract, canonical round-trip, unknown/missing/invalid fields, cross-field rules, the complete safety truth table, draft/save locking, retry/stale attempts, replacement ordering and failure preservation, and reset behavior.

## Production hardening verified in the final source

- Nil Bristol type persists as an explicit JSON `null` instead of disappearing or becoming an invented value.
- Fake-provider entries retain truthful UI-demo attribution after persistence; real entries retain the exact E4B CPU/Simulator runtime provenance.
- Synthetic demo classification uses an immutable marker, so Reset Demo cannot broaden to ordinary entries after a note edit.
- Automated evidence runners throw on failed acceptance instead of printing a misleading PASS marker.
- New Entry refreshes model readiness after the inference lab is dismissed.
- Runtime badges use truthful colors, long forms auto-scroll, and selected-image readiness copy reflects the actual gate.

## Exact commands

Run these from:

```text
/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-timeline
```

Host suite:

```sh
swift test
```

List available Simulator identifiers, then substitute only the selected arm64 iPhone Simulator identifier for `<SIMULATOR_UDID>`:

```sh
xcrun simctl list devices available
```

Current qualifying arm64 Simulator suite:

```sh
xcodebuild test \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath DerivedData \
  -skipPackageUpdates \
  -only-testing:GITimelineTests \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES
```

Deterministic UI-only journey (the explicit fake provider never counts as real Gemma):

```sh
xcodebuild test \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -destination 'platform=iOS Simulator,id=<SMALL_SIMULATOR_UDID>' \
  -derivedDataPath DerivedData \
  -skipPackageUpdates \
  -only-testing:GITimelineUITests/GITimelineUITests/testDeterministicDemoReviewPersistsAndResets \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES
```

The dark/Accessibility Extra Large result used the same test on the same smaller Simulator after applying those UI settings. The recorded result, not the fake provider, supports only `UI_ACCEPTANCE`.

Debug Simulator build:

```sh
xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath DerivedData \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES
```

Final Release regression command:

```sh
xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData-Release \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES
```

This final current-source run passed at 00:23:40 EDT.

## Important non-qualifying and failed experiments

- A generic Simulator test build attempted an x86_64 slice and failed against the arm64-only LiteRT-LM Simulator framework. It is not a current-source app regression; the qualifying command explicitly uses `ARCHS=arm64` and `ONLY_ACTIVE_ARCH=YES`.
- The first Gemma 4 E4B main-`GPU`/vision-`CPU` initialization parsed the model but failed Metal kernel creation with `texture binding has argument index 31 that is greater than 30`. The corrected Simulator configuration uses CPU/CPU and passed; the failed GPU configuration was not repeated unchanged.

## Git hygiene checkpoint

At 00:29 EDT, `git diff --cached --name-only` was empty and the documentation diff passed `git diff --check`. The 3.66 GB model remains ignored under `work/` and must not be staged. The worktree remains intentionally dirty, and the qualifying `.xcresult` remains under DerivedData and must not be staged. No checkpoint commit is authorized by this update.
