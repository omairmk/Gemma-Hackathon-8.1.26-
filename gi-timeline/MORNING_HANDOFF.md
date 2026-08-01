# GI Timeline morning handoff

Updated: 2026-08-01 00:36 EDT (America/New_York)

## 1. What works now

The strongest proven result is `SIMULATOR_GEMMA_POC_GO`. Real Gemma image analysis runs locally in the arm64 iPhone Simulator app. Brown, green, and non-target synthetic pixels produce distinct outputs; three strict structured runs pass without a crash; and the same provider completes Analyze -> editable review -> Save -> History -> terminate/relaunch -> reopen persistence through the production view-model and persistence path. Deterministic tap-driven UI automation, dark/accessibility coverage, visual inspection, six screenshots, 14/14 host tests, 31/31 app tests, and the final Release build also pass within their stated boundaries.

## 2. What is real Gemma versus what uses a test mock

`GEMMA_SMOKE_RESULTS.json`, `NORMAL_FLOW_REAL_GEMMA.json`, and `NORMAL_FLOW_RELAUNCH.json` are real-Gemma evidence. The two 1/1 UI runs use a deterministic fake provider available only behind the explicit `--ui-test-fake-gemma` launch argument; they prove UI behavior and persistence only. The fake did not produce the real image evidence and can never satisfy the real-Gemma gate. Persisted fake results remain labeled **UI demo · Gemma not connected**.

## 3. The exact Gemma model and where it ran

`litert-community/gemma-4-E4B-it-litert-lm`, artifact `gemma-4-E4B-it.litertlm`, immutable revision `28299f30ee4d43294517a4ac93abd6163412f07f`, 3,659,530,240 bytes, SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`. It ran as CPU/CPU locally inside the arm64 iPhone Simulator app: `SIMULATOR_LOCAL`.

## 4. Whether real image pixels affected the output

Yes. Brown pixels returned `BROWN` and strict brown output, green pixels returned `GREEN` and strict green output, and the geometric control returned `OTHER` plus strict `not_target_image`. This was a real image-plus-text request to E4B, not text-only generation or canned JSON.

## 5. Whether the physical iPhone build/install/test passed

No. The phone is visible, paired, unlocked, in Developer Mode, and ready through developer-service discovery, but `PHYSICAL_IPHONE_BUILD` is `BLOCKED` because the Debug target's `DEVELOPMENT_TEAM` is blank. Cable transport and roughly 12 GB free space are not confirmed. No physical install or inference result is claimed.

## 6. What the owner can test immediately in under three minutes

After unlocking the Mac if needed, launch `GI Timeline Lab` in the already-prepared Simulator, choose the bundled Brown image, prepare Gemma if requested, analyze, edit Form to `mushy`, save, open History, terminate/relaunch, and reopen the entry. The exact commands and taps are in `DEMO_RUNBOOK.md`; the six inspected reference screens are under `outputs/demo-screens/`.

## 7. The single next owner action if anything important remains blocked

Unlock the Mac if needed, then open the GI Timeline Debug target's **Signing & Capabilities** pane in Xcode and select your Apple development team. Enter any Apple credential yourself, then run the documented physical build/install. This is the single highest-leverage owner action toward a physical-iPhone result.

## Honest status block

```text
REAL_GEMMA_BACKEND: SIMULATOR_LOCAL
REAL_GEMMA_E2E: PASS
PHYSICAL_IPHONE_BUILD: BLOCKED
NORMAL_APP_FLOW: PASS
UI_ACCEPTANCE: PASS
OFFLINE_IPHONE: NOT_RUN
MORNING_LABEL: SIMULATOR_GEMMA_POC_GO
```

These are hackathon POC fields. Legacy `DEVICE_INFERENCE_STATUS` and `APP_END_TO_END_STATUS` remain unchanged and are not upgraded by Simulator evidence.

## Key evidence

- `GEMMA_SMOKE_RESULTS.json`: canonical six-run real image smoke record.
- `GEMMA_SMOKE_RESULTS.md`: readable model, timing, output, and acceptance summary.
- `NORMAL_FLOW_REAL_GEMMA.json`: real E4B analysis, human edit, save, image copy, History presence, and exact saved provenance.
- `NORMAL_FLOW_RELAUNCH.json`: entry, edited observation, image, and provenance reopened after process termination/relaunch.
- `TEST_RESULTS.md`: final 14/14 host, 31/31 arm64 app, two 1/1 smaller-device UI runs, and final Release build results.
- `DEMO_RUNBOOK.md`: safe build, launch, model-staging, evidence, and under-three-minute demo commands with sanitized placeholders.
- `outputs/demo-screens/01-new-entry.png`
- `outputs/demo-screens/02-sample-selected.png`
- `outputs/demo-screens/03-analyzing-real-gemma.png`
- `outputs/demo-screens/04-editable-result.png`
- `outputs/demo-screens/05-history-detail.png`
- `outputs/demo-screens/06-error-dark-accessibility.png`

No owner health photo was used. All inference evidence uses the bundled synthetic brown, green, and geometric control fixtures.

## Production hardening completed

- Explicit JSON `null` persistence for nil Bristol type.
- Truthful fake-provider attribution after persistence and exact real runtime provenance for real saves.
- Immutable synthetic-demo marker and reset safety.
- Evidence runners now throw when acceptance fails.
- New Entry refresh after inference-lab dismissal.
- Truthful badge colors, auto-scroll, and corrected selected-image readiness copy.

## Remaining boundaries

The app is as complete as unattended automation allowed. Developer Mode is freshly enabled and the phone is available, but `PHYSICAL_IPHONE_BUILD` remains `BLOCKED` solely until the owner selects the Debug development team. Cable transport and roughly 12 GB free space are still unconfirmed. `OFFLINE_IPHONE` remains `NOT_RUN`; neither Simulator evidence nor the hackathon POC label upgrades the legacy device/end-to-end statuses.

## Checkpoint commits

- `3110d80fb8e964d76498f1ec8eedd3358ea715e0` — `feat: prove Gemma 4 E4B simulator image flow`. This is the last known-green code checkpoint: host 14/14, arm64 app 31/31, both UI configurations 1/1, and the current-source Release build all passed before it was created, with no source changes between those checks and the commit.
- `docs: record simulator Gemma POC handoff` — the documentation/evidence checkpoint containing this file, the sanitized JSON evidence, and six screenshots.

Model weights, DerivedData/xcresults, credentials, device identifiers, and private logs are excluded from both checkpoints.
