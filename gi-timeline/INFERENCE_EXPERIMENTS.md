# Inference experiment ledger

Append-only. Supporting build experiments do not count as physical image-inference evidence.

## EXP-20260731-001 — exact dependency correction

- Timestamp: 2026-07-31T17:30:00Z
- Hypothesis: the official checksum-only correction commit resolves the v0.14 Swift package without changing its wrapper API.
- Intended variable: package requirement only, from tag `v0.14.0` to exact official revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`.
- Git state: committed as `7cdf223`.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro Max / iOS 26.5 simulator; no physical iPhone.
- Runtime: LiteRT-LM exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`.
- Model/image/request/configuration: not applicable; no model inference was attempted.
- Result: PASS for dependency resolution, 14 host tests, 11 then-current app tests, and arm64 simulator build/test.
- Failure stage: none.
- Interpretation: establishes only the reproducible dependency boundary.
- Next experiment: compile the model-free shared runtime and DEBUG lab without a physical-inference claim.

## EXP-20260731-002 — physical-device visibility

- Timestamp: 2026-07-31T18:05:00Z
- Hypothesis: the intended iPhone is connected and visible to CoreDevice.
- Intended variable: read-only device discovery; no app/device mutation.
- Git state: `7cdf223`.
- Command: `xcrun devicectl list devices` in the approved CoreDevice execution context.
- Sanitized result: `No devices found.` `xcodebuild -showdestinations` listed simulators only.
- Device model/iOS/signing/build: unavailable because no phone was visible; no identifier was recorded.
- Model/image/request/configuration: not applicable.
- Result: BLOCKED on owner connection/unlock/trust.
- Failure stage: physical-device environment boundary, before signing or installation.
- Interpretation: not an app, model, or inference failure.
- Next experiment: repeat read-only discovery after the owner connects and unlocks the intended iPhone.

## EXP-20260731-003 — isolated model-free DEBUG lab

- Timestamp: 2026-07-31T19:02:00Z
- Hypothesis: one shared production runtime can support a DEBUG-only synthetic lab while Release excludes lab resources and strings.
- Intended variable: add the verified-model capability, app-scoped runtime coordinator, DEBUG lab, and synthetic resources; no model or runtime configuration change.
- Git state: dirty implementation state based on `7cdf223`; this entry will remain as the pre-commit record.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro Max / iOS 26.5 simulator; no physical iPhone.
- Runtime: LiteRT-LM exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`.
- Planned first candidate: `google/gemma-3n-E2B-it-litert-lm` at `73b019b63436d346f68dd9c1dbfd117eb264d888`; artifact absent and not downloaded.
- Configuration compiled but not inference-tested: `.gpu`; vision `.cpu()`; `maxNumTokens=2048`; `topK=1`; `topP=1`; temperature `0`; seed `0`; prompt `gi-observation-v1`; `Message(contents:[.imageFile(path), .text(prompt)])`.
- Synthetic resources: brown, green, and project-authored geometric control; source and Xcode-processed bundle hashes are recorded in `DEVICE_INFERENCE_REPORT.md`.
- Checks: Debug arm64 simulator build PASS; 19 app tests PASS; 14 host tests PASS; Release arm64 simulator build PASS; Release bundle contains no lab fixtures and its binary contains none of `Device Inference Lab`, the probe prompt, or `.devdata_inference`.
- Initialization/inference/raw response/parser/repair/latency/memory: NOT_RUN; no model was present.
- Result: PASS supporting model-free simulator evidence only.
- Failure stage: none in the supporting build; physical build remains blocked before install.
- Next experiment: signed launch of isolated `com.omairmkhan.GITimeline.debug` on the intended iPhone, after explicit confirmation that an isolated app will be installed.

## EXP-20260731-004 — final model-free suite verification

- Timestamp: 2026-07-31T19:10:00Z
- Hypothesis: the current model-free implementation, including the latest manual-save-during-preparation coverage, passes the complete automated suite.
- Intended variable: verification only; no model, runtime, prompt, configuration, app data, or device state changed.
- Git state: dirty implementation state based on `7cdf223`; no model artifact or physical-device evidence is present.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro Max / iOS 26.5 simulator for the app suite; host-core suite on this Mac; no physical iPhone.
- Runtime: LiteRT-LM exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef` compiled by the app suite; no engine was initialized.
- Model/image/request/configuration: not exercised; no model was present or downloaded.
- Checks: 20/20 current app simulator tests PASS; 14/14 host-core tests PASS.
- Initialization/inference/raw response/parser/repair/latency/memory: NOT_RUN.
- Result: PASS supporting automated evidence only.
- Failure stage: none in the automated suites; physical build remains blocked before install.
- Interpretation: supersedes the suite-count snapshot in EXP-20260731-003 for the current tree, but does not establish model loading, image consumption, content dependence, performance, or offline behavior.
- Next experiment: signed launch of isolated `com.omairmkhan.GITimeline.debug` on the intended iPhone, after explicit confirmation that an isolated app will be installed.

## EXP-20260731-005 — shared-runtime and evidence hardening verification

- Timestamp: 2026-07-31T19:22:00Z
- Hypothesis: the model-free build remains reproducible after closing the final shared-runtime concurrency and evidence-integrity gaps.
- Intended variable: supporting code-hardening boundary only; no model, inference configuration, prompt, fixture bytes, physical device, or device state changed, and no inference experiment was run.
- Git state: dirty Phase-2 implementation based on full commit `7cdf22329b1c4ea7d6a2e3daf94f6c97e0af8f5f`; this exact base/dirty marker is embedded in DEBUG evidence records.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro / iOS 26.5 simulator; no physical iPhone.
- Runtime changes under test: one active service/engine slot, coordinator-gated import/verify/descriptor transitions, one exclusive structured-inference/repair lease, stale-safe receipt refresh, actual hardware identifier capture, retryable evidence persistence, and refusal of multi-variable lab runs.
- Model/image/request/configuration: not exercised; no model is present or downloaded.
- Checks: 22/22 current app simulator tests PASS; 14/14 host-core tests PASS; Debug bundle/resource isolation PASS; Release arm64 simulator build PASS; Release bundle contains no lab fixtures, lab/probe/evidence strings, or DEBUG candidate descriptors.
- Initialization/inference/raw response/parser/repair/latency/memory: NOT_RUN.
- Result: PASS supporting automated evidence only.
- Failure stage: none in the automated suites; physical build remains blocked before install.
- Interpretation: this supersedes the current-suite count in EXP-20260731-004 without upgrading any physical or model gate.
- Next experiment: repeat read-only CoreDevice discovery only after the owner completes the one cable/unlock/Trust checkpoint.

## EXP-20260731-006 — atomic coordinator-lease closeout

- Timestamp: 2026-07-31T19:39:04Z
- Hypothesis: a coordinator-owned operation lease acquired before the first adapter suspension closes the remaining scheduling window between coordinator dispatch and adapter busy-state registration.
- Intended variable: coordinator scheduling hardening and its gate regression test only; no model, runtime revision, inference configuration, prompt, fixture bytes, physical device, or device state changed, and no inference experiment was run.
- Git state: dirty Phase-2 implementation based on full commit `7cdf22329b1c4ea7d6a2e3daf94f6c97e0af8f5f`; the physical model-free build/launch milestone required for the next commit has not occurred.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro / iOS 26.5 simulator for the app suite; host-core suite on this Mac; no physical iPhone.
- Runtime change under test: prepare/probe now hold a transient coordinator lease; structured analysis holds a descriptor-and-draft-bound lease through repair or discard; import, verification, invalidation, and descriptor switching require the absence of any lease; stale release tokens are ignored.
- Model/image/request/configuration: not exercised; no model is present or downloaded.
- First attempt: the post-audit app test command failed during compilation before any test executed because the new receipt accessor lacked an explicit `return`; that one-line compile defect was corrected and the identical command was rerun.
- Checks: 23/23 current app simulator tests PASS at 15:37 ET; 14/14 host-core tests PASS at 15:38 ET; fresh Release arm64 simulator build PASS; Release identity remains `com.omairmkhan.GITimeline` / `GI Timeline`; Release bundle inspection found no lab fixture, lab/probe/evidence, or DEBUG candidate descriptor strings.
- Initialization/inference/raw response/parser/repair/latency/memory: NOT_RUN.
- Result: PASS supporting automated evidence only.
- Failure stage: the corrected first attempt was a source compilation failure; the final exact rerun has no automated-suite failure. Physical build remains blocked before install.
- Interpretation: this supersedes the current-suite and coordinator-concurrency snapshots in EXP-20260731-005 without upgrading any physical, model-integrity, content-dependence, performance, or offline gate.
- Next experiment: repeat read-only CoreDevice discovery only after the owner completes the one cable/unlock/Trust checkpoint.

## EXP-20260731-007 — connected-phone readiness discovery

- Timestamp: 2026-07-31T20:15:38Z
- Hypothesis: after the owner completes the cable/unlock/Trust checkpoint, CoreDevice and Xcode can identify the intended phone and determine the next physical-build boundary without mutating it.
- Intended variable: read-only physical-device discovery only; no signing setting, app, model, phone setting, or device data changed.
- Git state: dirty Phase-2 implementation based on full commit `7cdf22329b1c4ea7d6a2e3daf94f6c97e0af8f5f`; no model artifact or physical-build commit exists.
- Environment: Xcode toolchain; device identifier, user-provided name, exact OS build, product type, and hardware-capacity details are omitted from the public branch.
- Sanitized device result: exactly one wired, paired, booted physical iOS device was visible through CoreDevice. Runtime available/peak memory was not measured.
- Xcode destination result: the project lists one available physical `platform:iOS, arch:arm64` destination with name and identifier redacted and no destination-eligibility error.
- Installed-app safety check: exact queries for `com.omairmkhan.GITimeline` and `com.omairmkhan.GITimeline.debug` both stopped before results with `CoreDeviceError 10005`: Developer Mode disabled. Their installed states remain UNKNOWN; empty result counts were discarded as non-evidence.
- Model/image/request/configuration: not exercised; no model is present or downloaded.
- Build/sign/install/launch/inference/latency/memory/offline: NOT_RUN.
- Result: PASS for connection, pairing, sanitized hardware/OS discovery, and Xcode destination enumeration; BLOCKED for developer-app inspection and physical build on the owner-controlled Developer Mode setting.
- Failure stage: external device-readiness checkpoint before signing or installation; not an app, dependency, model, or inference failure.
- Next experiment: after the owner enables Developer Mode and completes the required restart/confirmation, repeat only read-only readiness and exact installed-bundle discovery before requesting any build/install authorization.

## EXP-20260731-008 — simulator launch readiness

- Timestamp: 2026-07-31T21:00:59Z
- Hypothesis: the isolated Debug app can install, launch, and remain open on the matching arm64 iPhone 17 Pro Max simulator while preserving the stricter physical-device privacy gate and Release isolation.
- Intended variable: simulator launch readiness only; no model, inference configuration, prompt, fixture bytes, physical phone, signing setting, or device data changed, and no inference experiment was run.
- Git state: dirty Phase-2 implementation based on full commit `7cdf22329b1c4ea7d6a2e3daf94f6c97e0af8f5f`; no model artifact or physical-build commit exists.
- Environment: Xcode 26.6 (17F113); arm64 iPhone 17 Pro Max / iOS 26.5 simulator; the connected physical iPhone was not mutated.
- First launch: FAIL before UI because dyld could not resolve embedded `CLiteRTLM.framework`; the app target lacked `@executable_path/Frameworks` in its runtime search paths.
- Second launch: FAIL before UI on a DEBUG assertion because the simulator filesystem does not report the iPhone data-protection class. The assertion was narrowed at compile time to non-simulator DEBUG builds; it remains strict on physical devices.
- Final launch: PASS. `com.omairmkhan.GITimeline.debug` installed and remained open at `New Entry`, with `Local model preparation required` and the model import control disabled because no exact artifact is staged.
- Regression checks: 23/23 arm64 app-target simulator tests PASS with 0 failures and 0 skips; 14/14 host-core tests PASS; Release arm64 simulator build PASS. Release contains embedded `CLiteRTLM.framework` and `@executable_path/Frameworks`, with no fixture files or scanned DEBUG lab, probe, evidence-directory, or candidate-descriptor strings.
- Model acquisition boundary: the official immutable E2B page was opened in Chrome. Hugging Face reports a manually gated repository; owner login and acceptance of Google's Gemma terms remain required. No model bytes were downloaded, imported, or initialized.
- Initialization/inference/raw response/parser/repair/latency/memory/offline: NOT_RUN.
- Result: PASS for supporting simulator launch readiness only; BLOCKED on the owner-controlled model-license/authentication checkpoint before any download.
- Interpretation: this does not establish physical-device launch, model loading, image consumption, content dependence, performance, privacy enforcement, or Airplane-Mode behavior.
- Next experiment: after the owner authenticates and accepts the Gemma terms, download only the pinned E2B artifact, verify exact size and SHA-256, retain the source, stage it in the Debug simulator container, and attempt engine initialization as supporting evidence.
