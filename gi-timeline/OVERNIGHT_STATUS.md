# GI Timeline overnight POC status

Updated: 2026-08-01 00:36 EDT (America/New_York)

## Current result

- **Current strongest tier:** `SIMULATOR_GEMMA_POC_GO`
- **Real backend:** `SIMULATOR_LOCAL`
- **Physical iPhone build:** `BLOCKED` pending owner development-team selection
- **Exact model:** `litert-community/gemma-4-E4B-it-litert-lm`
- **Artifact:** `gemma-4-E4B-it.litertlm`
- **Immutable source revision:** `28299f30ee4d43294517a4ac93abd6163412f07f`
- **Exact bytes:** `3,659,530,240`
- **SHA-256:** `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- **Execution location/configuration:** local arm64 iPhone Simulator; main backend `CPU`, vision backend `CPU`, `maxNumTokens=2048`, deterministic sampler (`topK=1`, temperature `0`)

This is real Gemma image inference in the arm64 DEBUG Simulator app, not a mock. The exact model was imported into the app, its durable receipt matches the descriptor, different synthetic image pixels produced meaningfully different responses, and that same shared provider completed the normal Analyze -> editable review -> Save -> History -> relaunch/reopen journey. This proves the Simulator POC tier only; it is not a physical-iPhone result.

## Verified milestones

| Milestone | Live result |
|---|---|
| Source artifact integrity | **PASS.** The retained source file matches the exact byte count and SHA-256 above. |
| DEBUG import and receipt | **PASS.** Copy, second size/hash verification, atomic promotion, and durable descriptor-matching receipt completed. The staged source was preserved. |
| Initial GPU experiment | **FAIL, recorded.** Main `GPU` plus vision `CPU` reached model parsing, then failed Metal kernel initialization: `texture binding has argument index 31 that is greater than 30`. This configuration was not retried unchanged. |
| Corrected runtime handoff | **PASS.** The coordinator now uses the DEBUG simulator's selected CPU configuration instead of silently constructing the old hard-coded GPU baseline. |
| CPU engine initialization | **PASS** in `3.91 s`. |
| Brown synthetic probe | **PASS:** real-model response `BROWN` in `7.17 s`. |
| Green synthetic probe | **PASS:** real-model response `GREEN` in `5.77 s`. |
| Pixel dependence | **PASS for brown versus green.** The only intended input change was synthetic image content, and the outputs differed meaningfully. |
| Non-target probe | **PASS:** real-model response `OTHER` in `5.67 s`. |
| Structured GI observation and strict validation | **PASS: 3/3 consecutive synthetic image analyses.** Control returned a strict `not_target_image` result in `9.10 s`; brown returned a strict brown/smooth-formed result in `8.15 s`; green returned a strict green/smooth-formed result in `8.15 s`. No repair, failure, or crash occurred. |
| Automated real-Gemma smoke | **PASS.** Brown -> `BROWN`, green -> `GREEN`, control -> `OTHER`; brown/green contrast, non-target distinction, strict validation, and three consecutive structured runs all passed through `SIMULATOR_LOCAL`. Cached fresh-process engine preparation was `0.43 s`; the earlier first preparation was `3.91 s`. |
| DEBUG/POC normal-flow selection | **PASS in code/tests.** `normalFlowSelection` resolves to the exact E4B descriptor only in DEBUG; `releaseSelection` remains `nil`. New Entry receives the shared coordinator's actual CPU configuration and local execution location for honest saved provenance. |
| Same real provider in normal app flow | **PASS.** Brown synthetic pixels reached the real E4B provider through `NewEntryViewModel`; strict output was reviewed, `form` was edited from `smooth_formed` to `mushy`, the entry saved as `ai_edited`, appeared in the History data source with its copied image, and persisted after a process-terminating relaunch. Saved provenance exactly records E4B, `simulator-cpu-v1`, and `SIMULATOR_LOCAL`. |
| arm64 simulator tests | **PASS: 31/31**, 0 failures at 2026-08-01 00:24:41 EDT, including one-repair success, failure/retry draft preservation, exact saved Simulator provenance, immutable demo-marker safety, and explicit JSON `null` persistence for nil Bristol type. |
| Host SwiftPM tests | **PASS: 14/14**, 0 failures at 2026-08-01 00:24:25 EDT. |
| Deterministic UI smoke | **PASS: 1/1** on the smaller full-screen iPhone 17e Simulator at 390 x 844 points in 50.854 s at 00:06:02 EDT. This explicit fake-provider test proves the interface only, never real Gemma. |
| Dark/accessibility UI smoke | **PASS: 1/1** on the same smaller Simulator in dark mode and Accessibility Extra Large in 75.595 s at 00:08:04 EDT. |
| Visual acceptance and screenshots | **PASS.** Six sanitized screens were captured and visually inspected across the large presentation and the smaller dark/accessibility error state under `outputs/demo-screens/`. |
| Current-source Release build | **PASS** at 2026-08-01 00:23:40 EDT: final arm64 iPhone Simulator rerun ended with `** BUILD SUCCEEDED **`. Release remains model-free by design. |
| Physical iPhone readiness | **PASS through pre-signing discovery.** The phone is booted, Developer Mode is enabled, it is paired and unlocked, its tunnel and developer-disk-image services are ready, and Xcode lists it as an arm64 iOS destination. Live transport reports `localNetwork`; a cable connection is not confirmed. Free space of roughly 12 GB is also not confirmed. |
| Physical iPhone signing/build | **BLOCKED.** The Debug target's `DEVELOPMENT_TEAM` is blank. A valid local Apple Development signing identity exists, but its details are deliberately omitted. The owner must select the team in Xcode; the agent will not enter credentials. No physical build/install result is claimed. |
| Legacy status fields | Unchanged: neither `DEVICE_INFERENCE_STATUS` nor `APP_END_TO_END_STATUS` is upgraded by this POC evidence. |

## Evidence locations

- Candidate identity, source verification, and configuration history: `MODEL_CANDIDATES.json`
- Runtime and evidence schema: `GITimeline/DeviceInferenceLab.swift`
- Consolidated sanitized smoke result: `GEMMA_SMOKE_RESULTS.json`
- Real-provider normal-flow result: `NORMAL_FLOW_REAL_GEMMA.json`
- Relaunch/persistence verification: `NORMAL_FLOW_RELAUNCH.json`
- Sanitized visual evidence: `outputs/demo-screens/01-new-entry.png` through `06-error-dark-accessibility.png`
- DEBUG run evidence written by the app: `Documents/.devdata_inference/<run-id>/evidence.json` in the isolated DEBUG simulator container, with `response.raw.txt` beside it when raw synthetic-only output exists. The changing container prefix and run UUIDs are intentionally omitted here.
- Regression results: the final arm64 Simulator XCTest run passed 31/31 at 00:24:41 EDT, the host SwiftPM suite passed 14/14 at 00:24:25 EDT, both smaller-device UI configurations passed 1/1, and the final Release build passed at 00:23:40 EDT. See `TEST_RESULTS.md`.

No model weight, app-container identifier, device identifier, credential, or personal image is recorded in this file.

## Final overnight timeline

| Time (EDT) | Milestone |
|---|---|
| 2026-07-31 23:29 | Six-run real E4B smoke completed: brown `BROWN`, green `GREEN`, control `OTHER`, then 3/3 strict structured runs without repair or crash. |
| 2026-07-31 23:34 | Same real provider completed normal analysis, editable review, `ai_edited` save, History/image verification, and terminate/relaunch/reopen persistence. |
| 2026-08-01 00:06:02 | Smaller-device deterministic UI baseline passed 1/1. |
| 2026-08-01 00:08:04 | Smaller-device dark plus Accessibility Extra Large UI run passed 1/1. |
| 2026-08-01 00:23:40 | Final current-source arm64 Release build passed. |
| 2026-08-01 00:24:25 | Final post-screenshot host suite passed 14/14. |
| 2026-08-01 00:24:41 | Final post-screenshot arm64 app suite passed 31/31. |
| 2026-08-01 00:35 | Created green code checkpoint `3110d80fb8e964d76498f1ec8eedd3358ea715e0` (`feat: prove Gemma 4 E4B simulator image flow`). |

## Production-hardening changes completed tonight

- Explicit JSON `null` persistence for a nil Bristol type.
- Truthful fake-provider attribution after persistence and saved real runtime provenance for real results.
- Immutable synthetic-demo marker and reset safety.
- Evidence runners throw when acceptance fails instead of printing a false-positive PASS path.
- New Entry refreshes model readiness after dismissing the inference lab.
- Runtime badges use truthful colors; long forms auto-scroll; selected-image readiness copy is corrected.

## Remaining blocker and next action

The Simulator POC, UI acceptance, screenshots, tests, and final Release build are complete. The physical Debug build remains **BLOCKED solely because the Debug target has no Apple development team selected**. Developer Mode is enabled and the phone is available; cable transport and roughly 12 GB free space remain unconfirmed. If the Mac is locked, unlock it locally, select the Apple development team for the Debug target in Xcode, then run the documented physical build/install. `OFFLINE_IPHONE` remains `NOT_RUN`.

The last known-green code commit is `3110d80fb8e964d76498f1ec8eedd3358ea715e0`. The separate `docs: record simulator Gemma POC handoff` checkpoint contains the morning packet, machine-readable evidence, and sanitized screenshots.
