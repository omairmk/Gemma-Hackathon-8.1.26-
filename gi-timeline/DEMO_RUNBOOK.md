# GI Timeline demo runbook

Updated: 2026-08-01 00:30 EDT (America/New_York)

## Under-three-minute live demo

This path uses the already-installed, already-verified E4B model in the isolated Debug Simulator app. Do not restage or reimport the 3.66 GB model for the normal demo.

1. Unlock the Mac. Confirm an iPhone Simulator is booted:

   ```sh
   xcrun simctl list devices booted
   ```

2. Replace `<SIMULATOR_UDID>` with the booted Simulator identifier and launch the isolated app:

   ```sh
   xcrun simctl launch --terminate-running-process '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug
   ```

3. On **New Entry**, verify the badge says **Gemma 4 E4B · iPhone Simulator** and the label says **Prototype — not medical advice**.
4. Under **Try a demo image**, tap **Brown**. If shown, tap **Prepare local model**; cached preparation was 0.43 seconds in the evidence run.
5. Tap **Analyze with Gemma**. The proven warm structured response took about 8 seconds.
6. In **AI-assisted observation**, change **Form** from `smooth formed` to `mushy`, then tap **Save Reviewed Entry**.
7. Open **History**, tap the new synthetic entry, and show the thumbnail, reviewed fields, `(edited)` attribution, and model ID.
8. To prove relaunch persistence, terminate and launch again, then reopen **History**:

   ```sh
   xcrun simctl terminate '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug
   xcrun simctl launch '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug --show-history
   ```

9. When finished, use **Reset Demo** in History. It removes only entries marked as bundled synthetic demo data.

Say this exactly if asked where inference ran: **“Gemma 4 E4B ran locally in the iPhone Simulator on this Mac. Physical-iPhone inference is not yet proven.”**

The six visually inspected reference screens are in `outputs/demo-screens/`, ordered from empty New Entry through the dark/accessibility error state. Screenshots illustrate the demo; `GEMMA_SMOKE_RESULTS.json` remains the real-inference authority.

## Safe build and install commands

Run from:

```text
/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-timeline
```

Discover an available arm64 iPhone Simulator and use its identifier in place of `<SIMULATOR_UDID>`:

```sh
xcrun simctl list devices available
```

Build Debug:

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

Install only the isolated Debug bundle:

```sh
xcrun simctl install '<SIMULATOR_UDID>' DerivedData/Build/Products/Debug-iphonesimulator/GITimeline.app
```

Confirm the installed identity before staging a model:

```sh
plutil -extract CFBundleIdentifier raw DerivedData/Build/Products/Debug-iphonesimulator/GITimeline.app/Info.plist
plutil -extract CFBundleDisplayName raw DerivedData/Build/Products/Debug-iphonesimulator/GITimeline.app/Info.plist
```

Expected values are `com.omairmkhan.GITimeline.debug` and `GI Timeline Lab`.

## Model integrity and first-time Simulator staging

The source must remain at:

```text
/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/work/models/gemma-4-E4B-it.litertlm
```

Verify it without modifying it:

```sh
stat -f '%z' /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/work/models/gemma-4-E4B-it.litertlm
shasum -a 256 /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/work/models/gemma-4-E4B-it.litertlm
```

Expected bytes: `3659530240`. Expected SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.

Resolve the changing Debug data-container path; do not save or publish the returned identifier:

```sh
xcrun simctl get_app_container '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug data
```

Substitute that returned path for `<DEBUG_DATA_CONTAINER>`, then stage a retained copy without overwriting an existing file:

```sh
mkdir -p '<DEBUG_DATA_CONTAINER>/Documents/Import'
cp -n /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/work/models/gemma-4-E4B-it.litertlm '<DEBUG_DATA_CONTAINER>/Documents/Import/gemma-4-E4B-it.litertlm'
stat -f '%z' '<DEBUG_DATA_CONTAINER>/Documents/Import/gemma-4-E4B-it.litertlm'
shasum -a 256 '<DEBUG_DATA_CONTAINER>/Documents/Import/gemma-4-E4B-it.litertlm'
```

Launch the app, tap **Import model**, then **Verify and import**. The app checks the staged size/hash, copies to a temporary destination, checks the installed copy again, promotes it atomically, writes a descriptor-bound receipt, and preserves the staged source. Never embed the model in the app bundle or Git.

## Re-run the real evidence harness

These DEBUG launch arguments use the same real coordinator as the app, not the UI-test fake. Each command writes sanitized JSON inside the Debug app's `Documents/.devdata_inference` directory. With `--console-pty`, stop the terminal attachment with Control-C only after the printed PASS marker appears; this does not delete app data.

```sh
xcrun simctl launch --terminate-running-process --console-pty '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug --run-overnight-gemma-smoke
xcrun simctl launch --terminate-running-process --console-pty '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug --run-overnight-normal-flow
xcrun simctl launch --terminate-running-process --console-pty '<SIMULATOR_UDID>' com.omairmkhan.GITimeline.debug --verify-overnight-normal-flow
```

The deterministic UI provider is enabled only by the explicit `--ui-test-fake-gemma` argument. Never use that argument for a real-Gemma demonstration or evidence run.

## Physical iPhone build/install after owner signing

Do not attempt this section until the owner selects the Debug development team in Xcode. Confirm cable transport, an unlocked/trusted phone, and roughly 12 GB free space first. Discover the device without copying its identifier into documentation:

```sh
xcrun devicectl list devices
```

Substitute the selected value for `<PHYSICAL_DEVICE_ID>` and build the isolated signed Debug app using the team already selected by the owner:

```sh
xcodebuild build \
  -project GITimeline.xcodeproj \
  -scheme GITimeline \
  -configuration Debug \
  -destination 'platform=iOS,id=<PHYSICAL_DEVICE_ID>' \
  -derivedDataPath /private/tmp/gi-timeline-device-derived-data \
  -skipPackageUpdates
```

Verify the built bundle ID is exactly the isolated Debug ID, then install and launch only that app:

```sh
plutil -extract CFBundleIdentifier raw /private/tmp/gi-timeline-device-derived-data/Build/Products/Debug-iphoneos/GITimeline.app/Info.plist
xcrun devicectl device install app --device '<PHYSICAL_DEVICE_ID>' /private/tmp/gi-timeline-device-derived-data/Build/Products/Debug-iphoneos/GITimeline.app
xcrun devicectl device process launch --terminate-existing --device '<PHYSICAL_DEVICE_ID>' com.omairmkhan.GITimeline.debug
```

Expected bundle ID: `com.omairmkhan.GITimeline.debug`. The first launch creates the app's shared Documents folders. Preserve the source model and transfer the exact artifact into the isolated app container:

```sh
xcrun devicectl device copy to \
  --device '<PHYSICAL_DEVICE_ID>' \
  --source /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/work/models/gemma-4-E4B-it.litertlm \
  --destination 'Documents/Import/gemma-4-E4B-it.litertlm' \
  --domain-type appDataContainer \
  --domain-identifier com.omairmkhan.GITimeline.debug
```

Alternatively, because file sharing is enabled, use Finder's Files pane to copy the same artifact into the GI Timeline Lab `Import` folder. In the app, tap **Import model** then **Verify and import**; do not bypass the size/hash receipt. Run only the bounded synthetic sequence. Never enter credentials through Codex, expose identifiers, delete another app/container, or call a Simulator result on-device. `OFFLINE_IPHONE` remains `NOT_RUN` unless Airplane Mode and a cold physical launch are actually observed.
