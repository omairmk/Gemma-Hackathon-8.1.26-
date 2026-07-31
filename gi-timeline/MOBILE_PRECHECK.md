STARTER_CODE_ALLOWED:
STATUS:
EVENT_STARTER_CODE_ALLOWED: UNANSWERED
DEVICE_INFERENCE_STATUS: IN_PROGRESS
APP_END_TO_END_STATUS: NOT_RUN

# GITimeline mobile precheck record

## REPO

| Field | Value |
|---|---|
| Project/app target build command | Exact official correction revision resolves; clean arm64 iPhone 17 Pro Max / iOS 26.5 simulator build passed. See `BUILD_STATUS.md`. |
| Test target build/test command | Clean exact-revision project: arm64 simulator `xcodebuild ... test` passed 11/11 app-target tests. |
| LiteRT-LM package | `https://github.com/google-ai-edge/LiteRT-LM.git` |
| LiteRT-LM tag/API base | `v0.14.0` |
| LiteRT-LM exact correction commit | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| `Package.resolved` present | Yes; exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`. |
| Bundle ID | `com.omairmkhan.GITimeline` |
| Model ID | No model selected; Gallery-pinned Gemma 3n E2B is the first-baseline candidate pending owner/device memory confirmation and download approval. |
| Prompt/validator example passes | Yes; included in 14/14 passing host tests. |

## INDEPENDENT GATES

| Axis | Verdict | Evidence/blocker |
|---|---|---|
| Dependency | PASS | Exact official correction revision resolves; 14 host and 11 arm64 simulator tests pass. |
| Physical device build | BLOCKED | Read-only CoreDevice query returned `No devices found`; owner must connect and unlock the intended iPhone. |
| Model integrity | NOT_RUN | No qualifying Gemma 3n LiteRT-LM iOS artifact is present locally. |
| Engine initialization | NOT_RUN | Requires verified model and physical iPhone. |
| Multimodal/content dependence | NOT_RUN | No physical image request has run. |
| Structured output | NOT_RUN | Parser tests pass; no physical model response exists. |
| Stability | NOT_RUN | Five-run device sequence has not run. |
| Offline cold launch | NOT_RUN | Owner-controlled Airplane Mode gate has not run. |
| Normal-app end to end | NOT_RUN | Physical review/save/history/relaunch/delete flow has not run. |

## PHONE

| Field | Value |
|---|---|
| Device identifier/model | |
| iOS version | |
| Xcode version | `26.6 (17F113)` on the Mac; no phone build run. |
| Signing identity/team | |
| Installed build | |
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
| Sampler temperature | `0` |
| Exact image+text message form | `Message(of: .imageFile(draftURL.path), .text(Self.prompt))`; compiled in the clean exact-revision project, not inference-tested. |

## PHYSICAL GATES

| Gate | Result/evidence |
|---|---|
| Gallery App Store install and Ask Image brown-prop cross-check | |
| E4B model load without OOM | |
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
- No physical iPhone is currently visible to CoreDevice.
- No qualifying iOS model artifact is present; a gated multi-gigabyte download requires owner terms acceptance and approval.
- Every PHONE and PHYSICAL GATES field above remains unrun and intentionally blank. Simulator/host passes do not substitute for exact-candidate loading, contrasting-image behavior, Airplane Mode, memory/latency, SwiftData CRUD, or device protection/deletion evidence.
