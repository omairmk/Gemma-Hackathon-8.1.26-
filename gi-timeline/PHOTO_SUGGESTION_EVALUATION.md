# Photo suggestion evaluation

Status: **baseline retained**. No accuracy candidate is installed as the production default.

This ledger is deliberately route-separated. A raw-image Simulator run and a physical-iPhone derived-map run answer different questions and are never combined.

## Frozen evaluation contract

The local, Git-ignored evaluation set was frozen at `2026-08-02T01:00:30Z`, before prompt or extractor tuning.

| Item | Frozen value |
|---|---|
| Manifest | `work/photo-evaluation/manifest.json` |
| Manifest SHA-256 | `7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20` |
| Tuning partition | 12 fixtures |
| Locked holdout | 12 fixtures |
| Referenced assets | 24 metadata-stripped JPEGs with an embedded sRGB profile |
| Content | Synthetic, non-health geometric or clay-like target constructions; quality degradations; ambiguous cases; and non-target controls |
| Bristol coverage by construction | Types 1 through 7, plus mixed and unable-to-assess cases |
| Quality/control coverage | Dark, glare, blur, crop, distance, brown, green, red, patterned, same-color/different-shape, same-shape/different-color, cold-start, and rotation cases |
| Real health photos | None |
| Independent labels | Not available |
| Qualified clinical reviewers | Not available |

The fixture labels describe how synthetic shapes were constructed. They are reference labels for engineering checks, not medical ground truth. The set cannot establish real-photo performance, clinical accuracy, or clinical effectiveness.

## Named routes and immutable versions

| Route | What Gemma receives | Baseline | Candidate | Current decision |
|---|---|---|---|---|
| `RAW_IMAGE_SIMULATOR` | The sanitized image, followed by the prompt, through the real image-message path | `gi-observation-raw-v1` / prompt `gi-observation-v1` | `gi-observation-raw-v2` / prompt `gi-observation-v2-debug` | Baseline completed; candidate incomplete after a generation stall; baseline retained |
| `DERIVED_MAP_IPHONE` | Text containing bounded facts from the local Swift pixel extractor; **Gemma does not receive the photo** | `gi-local-pixel-bridge-v1` | `gi-local-pixel-bridge-v2` | Baseline completed; candidate incomplete after the same generation-stall class recurred; baseline retained |

The raw prompt candidate is DEBUG-only. The derived-map candidate is opt-in. Neither is selected by `InferenceConfiguration.runtimeDefault`.

## Frozen holdout results

Both named routes now have current frozen-holdout evidence, but neither candidate completed. Results are never pooled across routes or attempts.

### `RAW_IMAGE_SIMULATOR`

The Debug arm64 Simulator build, in-place install, and launch succeeded. The launch validated the frozen manifest hash, all 24 asset hashes, metadata-free sRGB JPEG properties, route/configuration contract, and exact model receipt before inference. Gemma received each sanitized image through the real image-message path. This is raw-image Simulator evidence, not physical-iPhone evidence.

The single authorized run was `651AA1FF-6D8D-45BF-ACD1-0CD178D19A94`. Its baseline completed and persisted all 12 fixtures. Its candidate persisted the first four fixtures; generation for `h05-edge-cropped` then exceeded the 120,000 ms bound. CoreSimulator control also became temporarily unresponsive while the native call was blocked, so the exact app process was operator-terminated. Candidate percentages below describe only the four completed observations and are not an identical-holdout comparison.

| Metric | Baseline, complete | Candidate, partial |
|---|---:|---:|
| Holdout observations collected | 12 / 12 | 4 / 12; `h05` stalled |
| Reference-labeled observations | 4 | 3 observed |
| Exact Bristol agreement | 2 / 4 (50.0%) | 0 / 3 observed (0.0%) |
| Within-one-type agreement | 2 / 4 (50.0%) | 0 / 3 observed (0.0%) |
| Group agreement (`1–2`, `3–5`, `6–7`) | 2 / 4 (50.0%) | 0 / 3 observed (0.0%) |
| Correct abstention | 7 / 8 (87.5%) | 1 / 1 observed (100.0%) |
| Coverage | 4 / 12 (33.3%) | 0 / 4 observed (0.0%) |
| Coverage on reference-labeled observations | 3 / 4 (75.0%) | 0 / 3 observed (0.0%) |
| Strict-JSON validity | 12 / 12 (100.0%) | 4 / 4 observed (100.0%) |
| Bristol/form consistency | 12 / 12 (100.0%) | 4 / 4 observed (100.0%) |
| Direct / repaired / invalid parse | 12 / 0 / 0 | 4 / 0 / 0 observed |
| User-confirmed corrections | Not collected | Not collected |
| Mean completed-observation latency | 8,496.4 ms | 8,387.3 ms observed |
| Maximum completed-observation latency | 9,816.7 ms | 9,100.0 ms observed; run-level maximum is greater than 120,000 ms |
| Simulator process resident high-water mark | 8,250,048,512 bytes (7.68 GiB) | 8,250,048,512 bytes after four observations; stalled-observation sample unavailable |
| Persisted result failures / spontaneous crashes | 0 / 0 | 0 / 0 across the four completed observations |
| Generation stalls / operator terminations in this run | 0 / 0 | 1 / 1 |

Baseline confusion counts:

| Reference | Suggestion | Count |
|---|---|---:|
| `ABSTAIN` | `ABSTAIN` | 7 |
| `ABSTAIN` | `TYPE_4` | 1 |
| `TYPE_2` | `TYPE_4` | 1 |
| `TYPE_4` | `TYPE_4` | 2 |
| `TYPE_6` | `ABSTAIN` | 1 |

Partial-candidate confusion counts:

| Reference | Suggestion | Count |
|---|---|---:|
| `ABSTAIN` | `ABSTAIN` | 1 |
| `TYPE_2` | `ABSTAIN` | 1 |
| `TYPE_4` | `ABSTAIN` | 1 |
| `TYPE_6` | `ABSTAIN` | 1 |

Durable local evidence is Git-ignored:

| Evidence | SHA-256 |
|---|---|
| `work/photo-evaluation/simulator-results/651aa1ff-6d8d-45bf-acd1-0cd178d19a94/baseline-results.json` | `03841ea9e513719e0d93114e12a218f2b3762a28e4b60b9470fe2687c23cfa25` |
| `work/photo-evaluation/simulator-results/651aa1ff-6d8d-45bf-acd1-0cd178d19a94/candidate-results.json` | `6b65c6fe31645d1a3c5773aaed44b066916c138160203bfbcb218664c5ff1317` |
| `work/photo-evaluation/simulator-results/651aa1ff-6d8d-45bf-acd1-0cd178d19a94/active-checkpoint.json` | `503b26f0c79beb7501fee13e93dba6d7cc30df11cb96536c9d0de72e6e854291` |

No final `summary.json` exists because the candidate was stopped while its native generation call was blocked. The identical-set comparator correctly cannot run against 12 baseline and four candidate results. No second raw-image run or prompt tuning was attempted.

Existing historical Simulator proofs used different synthetic fixtures. They remain separate runtime/content-dependence context and are not pooled into these frozen-set metrics.

### `DERIVED_MAP_IPHONE`

The signed Hackathon build, in-place install, and launch each succeeded on a physical iPhone. The launch validated the frozen manifest hash, every asset hash, metadata-free sRGB JPEG properties, the named configurations, and the exact model receipt before inference. Those are separate execution gates; they do not make the candidate run complete or accurate. The in-place installs did not require uninstalling the app, and the frozen inputs remained present and hash-valid.

The authoritative metric source is bounded repeat run `3FDA8D7F-2B57-4EA0-97AE-92B43F3FD277`. Its baseline completed all 12 fixtures and was persisted. Its candidate persisted the first four fixtures; generation for `h05-edge-cropped` then exceeded the 120,000 ms bound and the app was operator-terminated. Candidate percentages below describe only those four completed observations. They are not a locked-holdout comparison.

| Metric | Baseline, complete | Candidate, partial |
|---|---:|---:|
| Holdout observations collected | 12 / 12 | 4 / 12; `h05` stalled |
| Reference-labeled observations | 4 | 3 observed |
| Exact Bristol agreement | 1 / 4 (25.0%) | 0 / 3 observed (0.0%) |
| Within-one-type agreement | 2 / 4 (50.0%) | 0 / 3 observed (0.0%) |
| Group agreement (`1–2`, `3–5`, `6–7`) | 2 / 4 (50.0%) | 0 / 3 observed (0.0%) |
| Correct abstention | 2 / 8 (25.0%) | 1 / 1 observed (100.0%) |
| Coverage | 10 / 12 (83.3%) | 0 / 4 observed (0.0%) |
| Coverage on reference-labeled observations | 4 / 4 (100.0%) | 0 / 3 observed (0.0%) |
| Strict-JSON validity | 12 / 12 (100.0%) | 4 / 4 observed (100.0%) |
| Bristol/form consistency | 12 / 12 (100.0%) | 4 / 4 observed (100.0%) |
| Direct / repaired / invalid parse | 12 / 0 / 0 | 4 / 0 / 0 observed |
| User-confirmed corrections | Not collected | Not collected |
| Mean completed-observation latency | 15,663.6 ms | 17,390.6 ms observed |
| Maximum completed-observation latency | 16,743.1 ms | 17,834.1 ms observed; run-level maximum is greater than 120,000 ms |
| Process resident high-water mark | 3,564,961,792 bytes (3.32 GiB) | 4,223,369,216 bytes (3.93 GiB) after four observations; stalled-observation sample unavailable |
| Persisted result failures / spontaneous crashes | 0 / 0 | 0 / 0 across the four completed observations |
| Generation stalls / operator terminations in this run | 0 / 0 | 1 / 1 |

Baseline confusion counts:

| Reference | Suggestion | Count |
|---|---|---:|
| `ABSTAIN` | `ABSTAIN` | 2 |
| `ABSTAIN` | `TYPE_4` | 3 |
| `ABSTAIN` | `TYPE_5` | 2 |
| `ABSTAIN` | `TYPE_6` | 1 |
| `TYPE_2` | `TYPE_4` | 1 |
| `TYPE_4` | `TYPE_4` | 1 |
| `TYPE_4` | `TYPE_5` | 1 |
| `TYPE_6` | `TYPE_4` | 1 |

Partial-candidate confusion counts:

| Reference | Suggestion | Count |
|---|---|---:|
| `ABSTAIN` | `ABSTAIN` | 1 |
| `TYPE_2` | `ABSTAIN` | 1 |
| `TYPE_4` | `ABSTAIN` | 1 |
| `TYPE_6` | `ABSTAIN` | 1 |

The initial bounded attempt, run `6499E550-F661-4F57-B5B5-578B12DD2C7A`, also completed the baseline (12 / 12) before candidate generation stalled, then on `h03-type6-mushy` after two candidate completions. The repeat moved past `h03` but stalled on `h05`. This is recurrence of the same candidate text-generation runtime-failure class on a different fixture, not a deterministic fixture classification failure. Both processes were deliberately terminated only after the bound was exceeded; no spontaneous app crash was observed. Per the stop rule, no third run or further metric tuning was attempted.

Durable local evidence is Git-ignored:

| Evidence | SHA-256 |
|---|---|
| `work/photo-evaluation/device-results/3fda8d7f-2b57-4ea0-97ae-92b43f3fd277/baseline-results.json` | `e249570cf61753c273e5c704266bf4aa40c9bf08a56fac1c17aef74b40f264dd` |
| `work/photo-evaluation/device-results/3fda8d7f-2b57-4ea0-97ae-92b43f3fd277/candidate-results.json` | `05d5914ef6e26ec5a8db8007518036a7a2a3f94d3f0157f77b6969fc59d1d95a` |
| `work/photo-evaluation/device-results/3fda8d7f-2b57-4ea0-97ae-92b43f3fd277/active-checkpoint.json` | `3947f0be6beeed55cd0dae30c6942adabdaaa51323b765b50be997b38ba28a43` |
| `work/photo-evaluation/device-results/6499e550-f661-4f57-b5b5-578b12dd2c7a/active-checkpoint.json` | `a3d2bda3567e6e84096d47060098114f7518d20d20ba2e8c4bbeb000feea0628` |

No final `summary.json` exists because each candidate run was stopped while its native generation call was blocked. The identical-set comparator correctly cannot run against 12 baseline results and four candidate results, so there is no adoption decision object and no defensible claim that the candidate is more accurate.

This route measures the deterministic Swift extractor plus Gemma's structured serialization. Gemma received bounded text facts, not image pixels. It is neither raw-photo Gemma visual evidence nor clinical evidence.

## Implemented safety and measurement contracts

- Bristol type and form are now an exact pair: `1↔hard_lumps`, `2↔lumpy_formed`, `3↔cracked_formed`, `4↔smooth_formed`, `5↔soft_blobs`, `6↔mushy`, and `7↔watery`. A null type is accepted only with `mixed` or `unable_to_assess`.
- Route-separated result models calculate exact, within-one, grouped, abstention, coverage, schema, repair, correction, latency, memory, failure, crash, and confusion counts. Empty denominators return no value rather than `NaN`.
- Candidate comparison requires the identical holdout fixture IDs and sanitized hashes. Adoption requires a strict exact-agreement improvement with no regression in the other safety, abstention, schema, repair, failure, crash, latency, or memory gates.
- Image preparation remains deterministic JPEG quality `0.80`, strips metadata, embeds sRGB, and verifies the prepared bytes by SHA-256.
- The derived-map candidate adds conservative target/quality abstention, connected-component cleanup, ROI/full-frame color agreement, and content-dependence checks. Unsupported shapes abstain instead of being forced to a nearby type.
- Derived-map postconditions reject any Gemma response that overrides extractor facts or changes either red/black field from `unable_to_assess`. The existing single same-conversation repair is allowed; a second repair is not.
- Logs contain the route, actual pipeline version, sanitized image hash, color space, grid, quality outcome, and parse path. They do not contain image bytes.
- The exact E4B artifact, LiteRT revision, sampler, context, saved seven-key schema, and production routing were not changed by this work.

## Automated contract evidence

On an iPhone 17 Pro Max Simulator running iOS 26.5:

- `PhotoSuggestionAccuracyTests`: **6 passed, 0 failed**. These checks cover immutable pipeline selection, conservative prompt ordering, deterministic metadata-free sRGB preparation, candidate content dependence, abstention on eight synthetic controls, and derived-map postconditions.
- `PhotoSuggestionEvaluationTests`: **11 focused evaluator tests passed** in the Swift package suite. These checks cover all Bristol/form contradictions, null rules, metrics, empty denominators, route separation, manifest validation, unsafe asset paths, frozen-holdout identity, sanitized-hash identity, and adoption/regression gates. The final full Swift package suite passed **38 / 38**.
- The final generic-device Hackathon configuration built and signed successfully with the pinned model receipt after the watchdog was moved onto an independent executor.

These are code-contract and synthetic tuning checks. They are not frozen-holdout route results and are not evidence that the candidate is more accurate.

## Adoption decision

**Baseline retained on both routes.** Each baseline completed its route-specific 12-item holdout, but neither candidate completed the identical set. The physical derived-map candidate exceeded the generation bound in two bounded attempts; the single raw-image Simulator candidate attempt also exceeded it at its fifth fixture. Both candidates therefore fail the completion and runtime gates before an accuracy comparison is possible. `PhotoCandidateComparator` was not invoked on either mismatched fixture set, no candidate was installed as the default, and `InferenceConfiguration.runtimeDefault` remains unchanged.

No further run or tuning was attempted after each route's stop rule fired. Any future reconsideration requires separately resolving and validating bounded cancellation, then collecting one complete baseline/candidate pair on the same untouched holdout under a newly authorized run. A bridge result must remain labeled `DERIVED_MAP_IPHONE`; it cannot satisfy a raw-image or physical raw-photo Gemma gate. A `RAW_IMAGE_SIMULATOR` result cannot satisfy a physical-iPhone gate. The later physical launch-only diagnostics below are a third, separate runtime ledger and are not pooled into either accuracy route.

## Post-freeze physical raw-image runtime diagnostic — 2026-08-02

These bounded diagnostics used the exact embedded E4B receipt and `physical-gpu-cpu-vision70-ctx1024-v1` configuration. Gemma received each sanitized synthetic fixture through `Content.imageFile(path)` plus the prompt; the local pixel bridge was disabled. The harness used an isolated in-memory store, suppressed `AppRootView`, wrote only sanitized checkpoints, and did not read or write the journal.

| Diagnostic | Result | Evidence boundary |
|---|---|---|
| Isolated brown at `3a50588` | **PASS** | Returned `BROWN`; preparation 13.849 s, request 3.336 s, total 17.223 s; peak RSS 3,104,194,560 bytes |
| Brown/green/control launch-only suite at `33b70a6` | **FAIL, 2/3** | Brown and green passed color plus direct strict structured checks with distinct canonical observations; control expected `OTHER` but returned `BROWN` and stopped before structured validation |
| Fresh-process control-only repeat at `3866084` | **FAIL** | The same verified control again returned `BROWN`; preparation 12.165 s, request 2.525 s, total 14.713 s; peak RSS 3,548,299,264 bytes |

The fresh-process repeat rules out same-conversation carryover as the explanation for the control failure. The result demonstrates that this pinned physical raw image-message path can execute and produce materially distinct brown/green structured observations, but the launch-only suite reproducibly fails non-target specificity and therefore does not earn physical raw PASS. Ordinary-flow three-fixture acceptance remains `NOT RUN`. Per the stop rule, no further prompt, model, dependency, backend, or retry experiment was attempted.

This addendum is not a locked-holdout comparison, candidate-adoption decision, production-default change, ordinary GI Journal flow, review/save/relaunch proof, offline proof, real-photo accuracy estimate, or clinical evidence. The frozen metrics and baseline-retained decision above are unchanged.

## Public-release build-3 bounded-generation diagnostic — 2026-08-02

A later authorized physical run, `9DBE897B-5A75-4351-89F1-549EAD146998`, used development-signed debug/Hackathon build `1.0 (3)` and the unchanged frozen `DERIVED_MAP_IPHONE` manifest. Baseline v1 persisted seven direct strict-JSON results before native generation blocked on `h08-brown-boot`; the checkpoint remained `running_baseline` beyond the 30-second generation deadline and independent 120-second watchdog. The process was operator-terminated after approximately 185 seconds. Candidate v2 never started (`0/12`), no `summary.json` or comparator result exists, and the production default remains baseline v1.

The incomplete baseline's maximum completed latency was `17,742.46 ms`, and its highest recorded RSS was `4,438,736,896` bytes. Partial exact agreement was `1/3` labeled fixtures and partial correct abstention was `1/4` controls. Those fractions are not an identical-holdout comparison and must not be used as adoption or clinical accuracy metrics.

Copied semantic evidence is Git-ignored:

| Evidence | SHA-256 |
|---|---|
| Original on-device `active-checkpoint.json` | `249210a5c8fd3fd466c523d20d2bac637f455704c5e3347a95c6ab248e07318a` |
| Original on-device `baseline-results.json` | `cd4f2667bf6b974f735c1960c61b492f59f76cf66980a33f2f4f6a30eb91fbf1` |
| Local semantic copy `work/photo-evaluation/device-results/9dbe897b-5a75-4351-89f1-549ead146998/active-checkpoint.json` | `87d06e60132b89135f72910959c83b92d6ea23f112dff163342c740c14fbaac9` |
| Local semantic copy `work/photo-evaluation/device-results/9dbe897b-5a75-4351-89f1-549ead146998/baseline-results.json` | `d82e208c61436e7f210cc77f8f2fc2d8361ccd0f4a48117ad6b721864b467773` |

The copied semantic files differ from their original device representations only by one final newline, confirmed by diff. This negative diagnostic exposed that the new stream deadline did not yet contain a native call blocked inside LiteRT-LM on the phone. It is not AppStore/TestFlight, ordinary-flow, Airplane Mode, accessibility, real-photo, or clinical evidence.

## Public-release build-4 memory/session diagnostic — 2026-08-02

Development-signed Hackathon/debug `1.0 (4)` from exact source commit `cdfa897421806b3bc3fd9b66e727664b40b4f225` installed in place and ran frozen `DERIVED_MAP_IPHONE` diagnostic `7EA6C93B-361E-4879-A831-6E566E3DE36D`, manifest SHA-256 `7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20`. Baseline v1 completed `12/12` with direct strict JSON and no 32-second deadline firing. Its one-run diagnostic measurements were exact labeled agreement `1/4`, correct control abstention `2/8`, maximum completed latency `18,958.96125 ms`, and peak RSS `5,165,154,304` bytes. These synthetic measurements are not clinical validation or a real-photo accuracy estimate.

Candidate v2 reached only its first fixture, `h01-type2-lumpy-formed`. Deliberate harness invalidation of the baseline engine created a second coordinator and preparation; LiteRT failed to memory-map its XNNPACK cache, then its per-layer embedder failed with `Cannot allocate memory`, and the process ended with signal 11. Candidate completion is therefore `0/12`, meaning no completed candidate results. No candidate-results file, summary, identical-set comparator, adoption decision, or production-default change exists. The containment contract did not pass this diagnostic because a native `SIGSEGV` bypasses Swift containment.

The stop rule allowed one run only; there was no retry, tuning, or default change. Because the candidate did not complete even its first fixture, there is no identical-set accuracy or resource comparison. The normal app relaunched successfully at 20:18:18. Public release remains **NO-GO**. The later build-5 result below supersedes only this build-4-time statement that session reuse was unverified; it does not change the frozen build-4 failure.

Git-ignored evidence is retained under `work/photo-evaluation/device-results/7ea6c93b-361e-4879-a831-6e566e3de36d/`. Original device SHA-256 values are `27ae3c3752bb62ff7a498f405383bd8dcf70d589f3456961f4aef18a2f9f4e73` for the checkpoint and `7b65ee789ce837b4af559b43b4ef18a1348a7f626f7f2aa5e3f47bfae8d9a373` for baseline results. Local semantic-copy hashes are `4f50ad2290d270801f57f6353a54b95c6aeb58b7a43e0cb58ab7a0d503fcb160` and `441314af154991a3a7c4c1f97f156d99b4469452c24324e83d2db833f3df2bab`, respectively.

## Public-release build-5 complete identical-holdout diagnostic — 2026-08-02

This result supersedes only the pending/unverified build-5 note above and preserves all earlier evidence. Development-signed Hackathon/debug `1.0 (5)` from exact source commit `9df1d4e1ccf0fe90093c7bf368e8ce9eb85d8cbd` installed in place with the full bundled application model: `litert-community/gemma-4-E4B-it-litert-lm`, artifact `gemma-4-E4B-it.litertlm`, revision `28299f30ee4d43294517a4ac93abd6163412f07f`, `3,659,530,240` bytes, SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.

The one exact frozen physical run was `97E2C2CC-8C41-4CA6-A114-0AE74CC596FB`, route `DERIVED_MAP_IPHONE`, started `2026-08-03T00:37:46Z`, finished `2026-08-03T00:45:26Z`, and used manifest SHA-256 `7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20`. `completeIdenticalHoldout=true`: baseline v1 and candidate v2 used the same 12 fixture IDs and sanitized-image hashes and completed `12/12` each. All 24 outputs were direct strict JSON and Bristol/form-consistent, with zero failures, repaired or invalid parses, crashes, timeouts, or 32-second containment/quarantine events.

At the v1-to-v2 transition, the same prepared LiteRT session remained live: there was no engine/threadpool teardown, loader initialization, model mmap, or second prepare. The only engine/threadpool shutdown occurred after candidate fixture 12 at final invalidation. The persisted terminal marker was `PHOTO_SUGGESTION_EVALUATION_PASS` with `recommendation=BASELINE_RETAINED`. The diagnostic console was then intentionally stopped with Control-C (`signal 2`), which was not a crash, and the normal app relaunched successfully at `20:47:14`.

| Metric | Baseline v1 | Candidate v2 |
|---|---:|---:|
| Exact labeled agreement | `1/4` | `0/4` |
| Within-one-type agreement | `2/4` | `0/4` |
| Grouped agreement | `2/4` | `0/4` |
| Correct control abstention | `2/8` | `8/8` |
| Total coverage | `10/12` | `0/12` |
| Reference-labeled coverage | `4/4` | `0/4` |
| Direct / strict / Bristol-form-consistent | `12/12` each | `12/12` each |
| Mean latency | `17694.099316 ms` | `19838.168916666666 ms` |
| Maximum latency | `19038.015958 ms` | `20674.542417 ms` |
| Peak recorded memory | `4,772,167,680` bytes | `4,772,167,680` bytes |

The comparator returned `adopted=false` and `BASELINE_RETAINED`. Its exact reasons were:

- `Locked-holdout exact Bristol agreement did not improve.`
- `Within-one-type agreement regressed.`
- `Clinically useful group agreement regressed.`
- `Coverage on reference-labeled fixtures regressed.`
- `Candidate latency regressed beyond the allowed margin.`

There was no retry, tuning, adoption, or production-default change. Evidence is Git-ignored at `work/photo-evaluation/device-results/97e2c2cc-8c41-4ca6-a114-0ae74cc596fb/`:

| Evidence | SHA-256 |
|---|---|
| `active-derived_map_iphone.json` | `d0c646946a6311b9e96db3ad9ae0c4593b9d92a7ee478928d91fa6e2cbd34672` |
| `summary.json` | `cff35719b08de63c8293491b4e6dbca9e5f32d59cc167420f89a67245690a0e4` |
| `baseline-results.json` | `e5720bb9fa1ccc605131d7d26e70fb6197d8b4e679164d95e253be96b34ba8c2` |
| `candidate-results.json` | `6b2cf0f540dfcb027f4a7c0abf7dc65152d402b2cafffa0c955d160f9b7623e1` |

Evidence boundary: `Swift inspected the sanitized image and Gemma received text facts only. This is not raw-photo Gemma evidence.` The fixtures are synthetic and non-health, not clinical validation or a real-photo accuracy estimate. This closes only the same-session derived-map runtime diagnostic; AppStore/TestFlight, ordinary-flow, persistence/data-preservation, Airplane Mode, accessibility, clinical, and supported-device qualification remain open. Public release remains **NO-GO**.

## Validation boundary

Photo suggestions remain unvalidated, editable observations for a private journal. This work provides no clinical validation, diagnostic claim, treatment recommendation, safety judgment, real-photo accuracy estimate, or comparison against independent gastrointestinal clinicians. Manual entry remains authoritative when analysis fails or abstains, and every suggestion requires human review before save.
