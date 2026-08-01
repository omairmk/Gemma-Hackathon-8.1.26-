STARTER_CODE_ALLOWED:
STATUS:
EVENT_STARTER_CODE_ALLOWED: UNANSWERED
DEVICE_INFERENCE_STATUS: BLOCKED
APP_END_TO_END_STATUS: NOT_RUN

> **2026-08-01 hackathon POC supersession.** Keep the two legacy fields above unchanged: they still refer to the original physical-device/offline gate. Later evidence supersedes the historical 23-test, absent-model, and Developer-Mode-disabled details below. Exact Gemma 4 E4B image inference, strict brown/green/control contrast, and the normal review/save/History/relaunch path pass locally in the arm64 iPhone Simulator; host tests pass 14/14, app tests pass 31/31, UI acceptance passes, six screenshots were inspected, and the final arm64 Release build passes. Developer Mode is now enabled and the phone is available, but the physical Debug build remains **BLOCKED** until the owner selects an Apple development team; cable transport and roughly 12 GB free space remain unconfirmed. `OFFLINE_IPHONE` remains `NOT_RUN`. See `MORNING_HANDOFF.md` for the current POC contract. The older sections below remain a timestamped historical record and must not be read as current readiness.

# GITimeline mobile precheck record

## REPO

| Field | Value |
|---|---|
| Project/app target build command | Exact official correction revision resolves; arm64 iPhone 17 Pro / iOS 26.5 Debug tests and Release build passed. See `BUILD_STATUS.md`. |
| Test target build/test command | PASS: 23/23 current-source arm64 iPhone 17 Pro simulator tests at 2026-07-31 15:37 ET. |
| LiteRT-LM package | `https://github.com/google-ai-edge/LiteRT-LM.git` |
| LiteRT-LM tag/API base | `v0.14.0` |
| LiteRT-LM exact correction commit | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| `Package.resolved` present | Yes; exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`. |
| Bundle ID | `com.omairmkhan.GITimeline` |
| Model ID | No model selected. First planned baseline only: `google/gemma-3n-E2B-it-litert-lm` at immutable revision `73b019b63436d346f68dd9c1dbfd117eb264d888`; artifact absent and not downloaded. |
| Prompt/validator example passes | Yes; included in 14/14 passing host tests. |
| Debug isolation | Simulator build passed as `com.omairmkhan.GITimeline.debug` / `GI Timeline Lab`; DEBUG includes the isolated lab, three synthetic fixtures, and probe path. |
| Release isolation | Fresh simulator build passed as `com.omairmkhan.GITimeline` / `GI Timeline`; built Release inspection found no lab fixtures, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings. |
| Selected-model record | `SELECTED_MODEL.json` intentionally absent; no candidate has physical acceptance. |

## INDEPENDENT GATES

| Axis | Verdict | Evidence/blocker |
|---|---|---|
| Dependency | PASS | Exact official correction revision resolves; 14/14 host tests passed at 15:38 ET and 23/23 arm64 simulator app tests passed at 15:37 ET on 2026-07-31. |
| Physical device build | BLOCKED | The connected iPhone is wired, paired, booted, and listed by Xcode, but developer-app inspection returned `CoreDeviceError 10005`: Developer Mode is disabled. No build/install was attempted. |
| Model integrity | NOT_RUN | No qualifying Gemma 3n LiteRT-LM iOS artifact is present locally; no model is selected. |
| Engine initialization | NOT_RUN | Requires verified model and physical iPhone. |
| Multimodal/content dependence | NOT_RUN | No physical image request has run. |
| Structured output | NOT_RUN | Parser tests pass; no physical model response exists. |
| Stability | NOT_RUN | Five-run device sequence has not run. |
| Offline cold launch | NOT_RUN | Owner-controlled Airplane Mode gate has not run. |
| Normal-app end to end | NOT_RUN | Physical review/save/history/relaunch/delete flow has not run. |

## PHONE

| Field | Value |
|---|---|
| Device identifier/model | UDID redacted; CoreDevice product type `iPhone18,2`, mapped by the installed Xcode device-trait database to iPhone 17 Pro Max. Xcode `DevicePerformanceMemoryClass=12`; runtime peak/available memory remains unmeasured. |
| iOS version | `26.5.2 (23F84)` |
| Xcode version | `26.6 (17F113)` on the Mac; no phone build run. |
| Signing identity/team | |
| Connection/readiness | Wired, paired, booted, CoreDevice tunnel connected; Xcode lists an arm64 iOS destination. Developer Mode disabled. |
| Installed build | UNKNOWN — the exact production/debug bundle queries were refused before results because Developer Mode is disabled. |
| Model final path | |
| Download SHA-256 | |
| Imported SHA-256 | |
| Finder source removed only after verified import | |

## ENGINE AND SAMPLER

| Field | Value |
|---|---|
| Engine backend | `.gpu` in source; not run on device. |
| Vision backend | `.cpu()` in source; not run on device. |
| `maxNumTokens` | `2048` |
| Sampler `topK` | `1` |
| Sampler `topP` | `1` |
| Sampler temperature | `0` |
| Sampler seed | `0` |
| Prompt version | `gi-observation-v1` |
| Exact image+text message form | `Message(contents: [.imageFile(path), .text(prompt)])`; compiled against the exact wrapper, not physically inference-tested. |

## PHYSICAL GATES

| Gate | Result/evidence |
|---|---|
| Gallery App Store install and Ask Image brown-prop cross-check | |
| Exact accepted model load without OOM | |
| Brown prop: usable and brown observation | |
| Green prop: usable and contrasting green observation | |
| Repeated brown output identical under greedy configuration | |
| Warm runs 2–5 latency (seconds) | |
| Peak memory across five consecutive analyses | |
| Five consecutive clean analyses | |
| Airplane Mode force-quit/cold relaunch/analyze | |
| SwiftData CRUD smoke on-device | |
| Draft lifecycle check | |
| DEBUG metadata assertion/log | |
| DEBUG protection assertion/log: Images, Drafts, store, WAL, SHM | |
| DEBUG deletion assertion/log | |

## KNOWN LIMITATIONS / NO-GO REASON

- `EVENT_STARTER_CODE_ALLOWED` is still unanswered; this blocks event eligibility, not private device testing.
- The dependency gate now passes at the exact official checksum-correction revision.
- The physical iPhone is visible and paired, but Developer Mode is disabled; developer-app inspection and physical build/install remain blocked.
- No qualifying iOS model artifact is present; a gated multi-gigabyte download requires owner terms acceptance and approval.
- The Debug lab is isolated under `com.omairmkhan.GITimeline.debug`; Release remains `com.omairmkhan.GITimeline` and excludes the lab fixtures/probe surface.
- `SELECTED_MODEL.json` is absent by design. The planned Gemma 3n E2B baseline is not a selected or physically verified model.
- Read-only PHONE discovery fields are now populated. Signing, installed-build identity, model paths/hashes, and every PHYSICAL GATES result remain unrun or unknown. Simulator/host passes do not substitute for exact-candidate loading, contrasting-image behavior, Airplane Mode, memory/latency, SwiftData CRUD, or device protection/deletion evidence.

## ONE NEXT OPERATOR ACTION

On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen, then stop. This authorizes only a repeated read-only readiness and exact installed-bundle check.
