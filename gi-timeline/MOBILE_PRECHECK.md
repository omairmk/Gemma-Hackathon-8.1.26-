STARTER_CODE_ALLOWED:
STATUS:

# GITimeline mobile precheck record

## REPO

| Field | Value |
|---|---|
| Project/app target build command | Exact remote pin: blocked before compile by upstream v0.14.0 checksum mismatch. Non-qualifying `/private/tmp` checksum overlay: arm64 simulator `build-for-testing` passed. See `BUILD_STATUS.md`. |
| Test target build/test command | Same non-qualifying overlay: arm64 iPhone 17 Pro / iOS 26.5 simulator `xcodebuild ... test` passed 11/11 app-target tests. |
| LiteRT-LM package | `https://github.com/google-ai-edge/LiteRT-LM.git` |
| LiteRT-LM tag | `v0.14.0` |
| LiteRT-LM commit | `80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6` |
| `Package.resolved` present | Yes; exact v0.14.0 / `80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6`. |
| Bundle ID | `com.omairmkhan.GITimeline` |
| Model ID | `litert-community/gemma-4-E4B-it-litert-lm` |
| Prompt/validator example passes | Yes; included in 14/14 passing host tests. |

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
| Exact image+text message form | `Message(of: .imageFile(draftURL.path), .text(Self.prompt))`; compiled in the non-qualifying overlay, not inference-tested. |

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

- `STARTER_CODE_ALLOWED` is still unanswered.
- The exact official remote LiteRT-LM v0.14.0 pin is blocked by an upstream release-manifest checksum mismatch; no dependency deviation is committed.
- Every PHONE and PHYSICAL GATES field above remains unrun and intentionally blank. Simulator/host passes do not substitute for E4B loading, contrasting-image behavior, Airplane Mode, memory/latency, SwiftData CRUD, or device protection/deletion evidence.
