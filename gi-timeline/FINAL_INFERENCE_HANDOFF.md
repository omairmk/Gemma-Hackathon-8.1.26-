# Final iPhone inference handoff

## Verdict

- `DEVICE_INFERENCE_STATUS: BLOCKED`
- `APP_END_TO_END_STATUS: NOT_RUN`
- Physical Gemma image inference has **not** been demonstrated.
- The phone is now visible: wired, paired, booted iPhone 17 Pro Max on iOS 26.5.2, listed by Xcode as an arm64 iOS destination.
- The named blocker is Developer Mode: exact installed-bundle inspection returned `CoreDeviceError 10005` before results, so installed state remains unknown and no build/install was attempted.
- `SELECTED_MODEL.json` is intentionally absent because no model has earned physical gates or owner acceptance.

## One next operator action

On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen, then stop.

Codex will then repeat read-only readiness and exact installed-bundle discovery. No signing change, app installation, model-terms acceptance, model download/import, inference run, Airplane-Mode change, or deletion is authorized by this checkpoint.

## Prepared, non-physical evidence

| Boundary | Evidence |
|---|---|
| LiteRT-LM | Exact official revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`; package resolution passes with checksum verification enabled |
| Host core | PASS: 14/14 tests at 2026-07-31 15:38 ET |
| App tests | PASS: 23/23 current-source arm64 iPhone 17 Pro simulator tests at 2026-07-31 15:37 ET |
| Debug isolation | Simulator build passed for `com.omairmkhan.GITimeline.debug` / `GI Timeline Lab`; DEBUG contains the lab, synthetic fixtures, and probe path |
| Release isolation | Fresh simulator build passed for `com.omairmkhan.GITimeline` / `GI Timeline`; built Release inspection found no fixture files, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings |
| Device | iPhone 17 Pro Max, iOS 26.5.2, wired/paired/booted; Xcode destination visible; Developer Mode disabled; no signed device build |

Simulator and source evidence do not satisfy a physical inference gate.

## Exact planned baseline, not a selected model

| Field | Value |
|---|---|
| Model | `google/gemma-3n-E2B-it-litert-lm` |
| Artifact | `gemma-3n-E2B-it-int4.litertlm` |
| Immutable revision | `73b019b63436d346f68dd9c1dbfd117eb264d888` |
| Expected bytes | `3,388,604,416` |
| Trusted SHA-256 | `6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5` |
| Candidate gate | Gallery iOS allowlist snapshot at commit `87822fdabe82cf63e7cd369be55538de5dcc38ae`; minimum-memory field `6 GB`, still requiring confirmation against the actual phone |
| LiteRT-LM revision | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Engine | backend `.gpu`; vision backend `.cpu()`; `maxNumTokens=2048` |
| Sampler | `topK=1`; `topP=1`; temperature `0`; seed `0` |
| Prompt | `gi-observation-v1` |
| Request form | `Message(contents: [.imageFile(path), .text(prompt)])` |

The artifact is absent and no bytes were downloaded. This descriptor is only the first planned experiment if a later, separately authorized device check confirms eligibility.

## Gates still not run

Model integrity, engine initialization, pixel-dependent dominant-color behavior, structured brown/green/non-target outputs, repeatability, five-run stability, latency, peak memory, Airplane-Mode cold launch, SwiftData device smoke, file-protection logs, and the normal review/save/relaunch/delete flow all remain `NOT_RUN`.
