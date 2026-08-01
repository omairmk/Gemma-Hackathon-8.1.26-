# GI Timeline demo runbook

Updated: 2026-08-01 14:36 EDT (America/New_York)

## Current truth

`GITimeline Hackathon` embeds the exact verified Gemma 4 E4B model. The ordinary Debug and Release apps remain model-free. The optimized signed arm64 Hackathon artifact passes signature, bundle-identity, model-integrity, receipt, and production-surface checks. Fresh current-source arm64 Simulator evidence passes real brown/green/control image inference, automatic review/edit/save/History, and terminate/relaunch persistence.

The physical iPhone is not currently visible to Xcode, so the optimized artifact has not been installed or launched on that phone. Physical image inference and Airplane Mode remain blocked. Simulator and deterministic UI-test evidence never upgrades those physical gates.

## 60-second product demo

1. Open **GI Timeline** and tap **Continue** if the first-run explanation appears.
2. On **New Entry**, tap **Choose a photo** or **Take a photo**. Attaching the photo immediately opens **Reading photo**; there is no model picker, Import, Prepare, or Analyze control.
3. On **Review entry**, open each Suggested row, confirm or edit it, then tap **Save reviewed entry**. Save stays disabled until all five observations are reviewed.
4. Tap **View entry**, then **History**, and open the saved entry. The reviewed values and thumbnail remain after terminate/relaunch.

Use only the bundled synthetic fixtures for engineering acceptance. The screenshots in `outputs/demo-screens/` show the seven native states and the recoverable error state. They use the deterministic UI provider and prove interface behavior only.

## Build the embedded Hackathon app

Run from the `gi-timeline` directory. On a new checkout, select the local Apple development team in Xcode; signing values are intentionally not committed.

```sh
GI_DERIVED_DATA="${TMPDIR%/}/GITimeline-Embedded-Signed-Optimized"

xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme 'GITimeline Hackathon' \
  -configuration Hackathon \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$GI_DERIVED_DATA"

GI_APP="$GI_DERIVED_DATA/Build/Products/Hackathon-iphoneos/GITimeline.app"
```

The build must fail if `../work/models/gemma-4-E4B-it.litertlm` is missing or does not match the pinned size and SHA-256. Never commit or upload that file.

Verify the resulting artifact:

```sh
plutil -extract CFBundleIdentifier raw "$GI_APP/Info.plist"
codesign --verify --deep --strict "$GI_APP"
lipo -archs "$GI_APP/GITimeline"
find "$GI_APP" -type f -name '*.litertlm'
stat -f '%z' "$GI_APP/EmbeddedModels/gemma-4-E4B-it.litertlm"
shasum -a 256 "$GI_APP/EmbeddedModels/gemma-4-E4B-it.litertlm"
```

Expected values:

- Bundle ID: `com.omairmkhan.GITimeline.debug`
- Architecture: `arm64`
- Exactly one model file
- Bytes: `3659530240`
- SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`

## Physical iPhone acceptance

First reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. Resolve the live device identifier locally and never paste it into documentation, logs, or Git.

Install without uninstalling or deleting existing app data:

```sh
GI_DEVICE_ID='<resolved locally>'
xcrun devicectl device install app --device "$GI_DEVICE_ID" "$GI_APP"
```

Run the bounded synthetic-only acceptance harness one stage at a time:

```sh
xcrun devicectl device process launch --terminate-existing --console \
  --device "$GI_DEVICE_ID" com.omairmkhan.GITimeline.debug \
  --run-embedded-gemma-smoke

xcrun devicectl device process launch --terminate-existing --console \
  --device "$GI_DEVICE_ID" com.omairmkhan.GITimeline.debug \
  --run-embedded-gemma-normal-flow

xcrun devicectl device process launch --terminate-existing --console \
  --device "$GI_DEVICE_ID" com.omairmkhan.GITimeline.debug \
  --verify-embedded-gemma-normal-flow
```

Required markers:

- `EMBEDDED_GEMMA_SMOKE_PASS`
- `EMBEDDED_GEMMA_NORMAL_FLOW_PASS`
- `EMBEDDED_GEMMA_RELAUNCH_PASS`

Any `EMBEDDED_GEMMA_COMPLETION_FAIL` is a failure. Smoke qualifies only when real image pixels yield brown=`BROWN`, green=`GREEN`, control=`OTHER`, and all strict structured responses validate. The normal-flow marker must also record a human edit, save, History presence, and exact model/backend provenance; the relaunch marker must reopen that saved record.

## Simulator acceptance

The same embedded artifact can be built for the arm64 Simulator using the documented CPU-engine/CPU-vision exception:

```sh
GI_SIM_DERIVED_DATA="${TMPDIR%/}/GITimeline-Embedded-Simulator-Current"

xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme 'GITimeline Hackathon' \
  -configuration Hackathon \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' \
  -derivedDataPath "$GI_SIM_DERIVED_DATA" \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Install the app on the selected Simulator and launch the same three arguments above with `xcrun simctl launch --terminate-running-process --console-pty`. Use a locally resolved Simulator identifier and do not record it. The real-Gemma JSON outputs belong in Application Support under `CompletionEvidence`; only sanitized synthetic results may be copied into this repository.

## Airplane Mode proof

Only after the online physical sequence passes:

1. Ask the owner to enable **Airplane Mode**, confirm Wi-Fi is off, and leave the iPhone unlocked.
2. Force-quit and cold-launch the same installed app.
3. Analyze a fresh synthetic fixture, review every field, edit one, save, open History, terminate/relaunch, and reopen it.
4. Record `OFFLINE_IPHONE: PASS` only after that complete physical sequence is observed.

An embedded model, a Simulator run, or a successful online launch cannot establish offline operation.
