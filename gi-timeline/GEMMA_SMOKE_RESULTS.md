# Gemma 4 E4B smoke results

Updated: 2026-08-01 00:30 EDT (America/New_York)

## Verdict

**PASS for `SIMULATOR_GEMMA_POC_GO`.** Real synthetic image pixels reached the exact Gemma 4 E4B LiteRT-LM model locally inside the arm64 iPhone Simulator app. Brown, green, and geometric non-target pixels produced the expected distinct results; three consecutive structured analyses passed strict validation without repair or crash. The same real provider then completed the normal review/save/History/relaunch path.

This is not mock evidence, not a physical-iPhone result, and not an offline-iPhone result.

## Exact model and runtime

| Field | Value |
|---|---|
| Model | `litert-community/gemma-4-E4B-it-litert-lm` |
| Artifact | `gemma-4-E4B-it.litertlm` |
| Immutable revision | `28299f30ee4d43294517a4ac93abd6163412f07f` |
| Bytes | `3,659,530,240` |
| SHA-256 | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` |
| Execution location | `SIMULATOR_LOCAL` |
| Engine / vision backend | `CPU` / `CPU` |
| Context capacity | `maxNumTokens=2048` |
| Sampler | `topK=1`, `topP=1`, temperature `0`, seed `0` |
| Prompt | `gi-observation-v1` |
| Request | `Message(contents:[Content.imageFile(path),Content.text(prompt)])` |

The retained source, installed copy, and durable receipt were matched to the exact descriptor before inference.

## Real image smoke

The canonical machine-readable record is `GEMMA_SMOKE_RESULTS.json`.

| Run | Real output | Validation | Warm inference |
|---|---|---|---:|
| Brown dominant-color fixture | `BROWN` | exact-token PASS | 6.10 s |
| Green dominant-color fixture | `GREEN` | exact-token PASS | 5.66 s |
| Geometric non-target control | `OTHER` | exact-token PASS | 5.67 s |
| Geometric control structured | unusable / `not_target_image` | strict PASS; no repair | 9.10 s |
| Brown structured | usable; Bristol 4; brown; `smooth_formed` | strict PASS; no repair | 8.15 s |
| Green structured | usable; Bristol 4; green; `smooth_formed` | strict PASS; no repair | 8.15 s |

- Brown-versus-green content dependence: **PASS**.
- Non-target distinction: **PASS**.
- Consecutive structured stability: **PASS 3/3**, with no repair, failure, or crash.
- Fresh-process preparation with an existing runtime cache: **0.43 s**.
- First-ever observed preparation before that cache existed: **3.91 s**.

## Same real provider in the normal app flow

`NORMAL_FLOW_REAL_GEMMA.json` records a brown synthetic image reaching the shared real E4B coordinator through the normal `NewEntryViewModel` path. The strict result was exposed for review, `form` was edited from `smooth_formed` to `mushy`, and the entry saved with `ai_edited` provenance. The History data source contained the entry and copied image.

`NORMAL_FLOW_RELAUNCH.json` records a process-terminating relaunch followed by successful reopen of the same reviewed observation, edited form, image, and exact model/configuration/location provenance. Outcome: **PASS**.

## Boundaries kept honest

- The initial GPU experiment failed in Metal kernel initialization; only the proven CPU/CPU configuration is reported as working.
- A deterministic fake provider exists solely for repeatable UI automation. It did not produce any result in this smoke record and cannot satisfy real-Gemma acceptance.
- UI acceptance is **PASS** through two deterministic fake-provider runs on the smaller full-screen iPhone 17e Simulator: the baseline journey passed 1/1, and dark mode plus Accessibility Extra Large passed 1/1. These runs prove only the interface and persistence, not Gemma.
- Six sanitized screenshots were visually inspected under `outputs/demo-screens/`; the real-smoke JSON, not screenshots, remains the authority for actual Gemma inference.
- The physical iPhone is ready through developer discovery, but its signed build remains `BLOCKED` by the blank Debug development team.
- `OFFLINE_IPHONE` remains `NOT_RUN`.
- Legacy `DEVICE_INFERENCE_STATUS` and `APP_END_TO_END_STATUS` are not upgraded by this POC result.
