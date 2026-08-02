# GI Timeline test results

> **Historical evidence note:** Timings and device availability below are the 14:40 EDT snapshot. The current phone architecture and final claim boundary are in the repository root `README.md` and `DEVICE_INFERENCE_REPORT.md`. Publication revalidation passed the host suite 14/14 and arm64 app suite 41/41 on 2026-08-01.

Updated: 2026-08-01 14:40 EDT (America/New_York)

## Current verdict

Every unblocked build, regression, release-isolation, native-UI, and current-source Simulator real-Gemma gate in this snapshot is green. Later phone evidence passed the disclosed local pixel-facts → embedded Gemma text bridge through persistence. Physical raw-image Gemma and Airplane Mode remain blocked.

## Result matrix

| Check | Result |
| --- | --- |
| Host SwiftPM suite | **PASS: 14/14**, 0 failures at 14:24:30 EDT |
| Arm64 app suite | **PASS: 41/41**, 0 failures or skips in publication revalidation |
| Final exact-current UI suite | **PASS: 3/3** in 106.895 s |
| Large iPhone Simulator UI journey | **PASS: 3/3** |
| Smaller iPhone Simulator UI journey | **PASS: 3/3** |
| Dark + Accessibility Extra Large History layout | **PASS: 1/1** in 57.863 s |
| Dark + Accessibility Extra Large clean Detail capture | **PASS: 1/1** in 66.577 s |
| Visual inspection | **PASS:** seven native states plus recoverable error retained under `outputs/demo-screens/` |
| Optimized signed Hackathon build | **PASS:** full 45.56 s; post-cleanup incremental 14.87 s |
| Signed artifact identity | **PASS:** `com.omairmkhan.GITimeline.debug`, arm64, strict signature |
| Embedded model | **PASS:** exactly one file, exact bytes/SHA-256, matching receipt |
| Optimized app size | **3,619,184 KiB** |
| Hackathon production-surface audit | **PASS:** optimization on, testability/debug dylib off, no UI-test/mock/import/lab surface |
| Model failure shields | **PASS:** missing source, wrong byte count, and wrong SHA-256 fail the build |
| Incremental embed reuse | **PASS:** a verified unchanged destination is not recopied |
| Ordinary Release build | **PASS:** `com.omairmkhan.GITimeline`, arm64, zero model files, no Hackathon/debug surface |
| Current embedded Simulator build/install | **PASS:** build 43 s; install 4 s; CPU engine/CPU vision |
| Current embedded Simulator real-Gemma smoke | **PASS:** brown=`BROWN`, green=`GREEN`, control=`OTHER`; structured 3/3 |
| Current embedded Simulator normal flow | **PASS:** automatic review, edit, save, History, exact provenance |
| Current embedded Simulator relaunch | **PASS:** entry, reviewed edit, image, and provenance reopened |
| Current optimized physical install/launch | **BLOCKED:** fresh sanitized device list returned no physical iOS devices |
| Physical Gemma image inference/save/relaunch | **BLOCKED** |
| Physical Airplane Mode cold run | **BLOCKED** |
| Worktree validation | **PASS:** `git diff --check` |

The UI tests use an explicit deterministic provider and establish UI behavior only. They do not contribute to real-Gemma acceptance.

Fresh real-Gemma Simulator evidence is stored in `EMBEDDED_SIMULATOR_SMOKE.json`, `EMBEDDED_SIMULATOR_NORMAL_FLOW.json`, and `EMBEDDED_SIMULATOR_RELAUNCH.json`. Model preparation took 6.18 seconds; the six smoke image calls took 5.54–8.61 seconds. The normal-flow evidence itself completed in 8 seconds.

## Coverage highlights

The app suite covers bundled-model resolution and receipt invalidation, strict identity checks, one runtime initialization path, readiness gating, non-nil vision configuration, automatic analysis after photo attachment, stale-result rejection, cancellation/failure recovery, Suggested/Confirmed/Edited review states, review-before-save, provenance, persistence rollback, single-row retry behavior, relaunch persistence, and safe deletion/reset behavior.

The host suite covers the strict parser, canonical round-trip, missing/unknown/invalid fields, cross-field rules, safety rules, draft/save locking, stale work, retry, replacement failure preservation, and reset behavior.

The UI suite covers first run, New Entry, Reading photo, editable Review, review-gated Save, Saved, History, relaunch persistence, Entry Detail, delete/reset, and a recoverable error with the selected photo preserved. The final screenshots use dark mode and Accessibility Extra Large.

## Reproduction commands

Run from `gi-timeline/`.

Host tests:

```sh
swift test
```

Arm64 app tests:

```sh
xcodebuild test \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -derivedDataPath "${TMPDIR%/}/GITimeline-App-Tests" \
  -skipPackageUpdates \
  -only-testing:GITimelineTests \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

UI tests:

```sh
xcodebuild test \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -derivedDataPath "${TMPDIR%/}/GITimeline-UI-Tests" \
  -skipPackageUpdates \
  -only-testing:GITimelineUITests \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Model-free Release regression:

```sh
xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${TMPDIR%/}/GITimeline-Release" \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Use `DEMO_RUNBOOK.md` for the embedded build and the synthetic real-Gemma harness. Model weights, signing values, device identifiers, result bundles, DerivedData, private logs, and personal images are not repository evidence and must not be committed.
