# Physical iPhone inference report

Report date: 2026-07-31

## Verdict

Gemma image analysis on the owner's physical iPhone is **not yet demonstrated**.

- `DEVICE_INFERENCE_STATUS: BLOCKED`
- `APP_END_TO_END_STATUS: NOT_RUN`
- Named blocker: the connected iPhone is visible, paired, and listed by Xcode, but CoreDevice returned error `10005` when inspecting developer apps because Developer Mode is disabled.
- No signed device build, model import, engine initialization, image request, content-dependence output, five-run sequence, memory/latency measurement, or Airplane-Mode run occurred.
- `SELECTED_MODEL.json` is intentionally absent because no candidate has earned physical GO or owner acceptance.

## Exact runtime prepared for the next device experiment

| Field | Value |
|---|---|
| LiteRT-LM source | `https://github.com/google-ai-edge/LiteRT-LM.git` |
| Exact revision | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Backend | `.gpu` |
| Vision backend | `.cpu()` (non-nil) |
| Context/KV-cache capacity | `2048` |
| Sampler | `topK=1`, `topP=1`, temperature `0`, seed `0` |
| Prompt version | `gi-observation-v1` |
| Image-plus-text form | `Message(contents: [.imageFile(path), .text(prompt)])` |
| Draft source | the existing sanitized immutable `ImageStore` draft only |
| Engine ownership | one app-scoped runtime coordinator, one active adapter/service total, and an exclusive inference/repair lease |

The [official Swift guide](https://developers.google.com/edge/litert-lm/swift) documents multimodality, a non-nil vision backend, and image-plus-text messages. Compilation against the exact wrapper is supporting evidence; only a physical image request can establish runtime behavior.

## Candidate matrix result

`MODEL_CANDIDATES.json` contains immutable records for four separately named artifacts. No bytes were downloaded.

- First baseline, conditional on the actual phone meeting the live 6 GB memory gate: Gallery-pinned Gemma 3n E2B, revision `73b019b63436d346f68dd9c1dbfd117eb264d888`, 3,388,604,416 bytes, trusted SHA-256 `6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5`.
- Larger iOS-allowlisted candidate: Gemma 3n E4B, revision `3d0179a0648381585ab337e170b7517aae8e0ce4`, 4,652,318,720 bytes, trusted SHA-256 `510f7db80143308f788ded208784b6c8addabe4d465ca32fd5bd80fd43ed4dcb`.
- Current Gemma 4 E2B/E4B non-web artifacts are image-capable and Android-Gallery-allowlisted but are **not** in the current iOS allowlist. Their Android memory fields are not reused as iOS gates. They remain distinct research candidates, not silent substitutes.

Source snapshot accessed 2026-07-31:

- Gallery commit: `87822fdabe82cf63e7cd369be55538de5dcc38ae`
- [Immutable iOS allowlist](https://raw.githubusercontent.com/google-ai-edge/gallery/87822fdabe82cf63e7cd369be55538de5dcc38ae/model_allowlists/ios_1_0_0.json), file SHA-256 `9e6f3526040a5fa66fe97e24c931606caa20b0248da08169abb040e6a691ed91`
- [Immutable Android allowlist](https://raw.githubusercontent.com/google-ai-edge/gallery/87822fdabe82cf63e7cd369be55538de5dcc38ae/model_allowlists/1_0_15.json), file SHA-256 `10c3694e2e114afafc1ac8ca8d50496c6798a207fc7fbe77ab99df1a853490f9`
- [Gemma 3n E2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) and [Gemma 3n E4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-lm)
- [Gemma 4 E2B](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) and [Gemma 4 E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)

## Synthetic fixtures

All fixtures are project data with no real health information. Xcode's `CopyPNGFile` removes PNG text chunks, so the tracked-source and loaded-bundle hashes are intentionally recorded separately.

| Fixture | Provenance | Tracked PNG SHA-256 | Debug bundle SHA-256 | Dimensions |
|---|---|---|---|---|
| Brown | Existing project synthetic watermarked clay prop | `de793203c6665ecddf280092d2c09154d3e91abd254e078f04ff1c118f3490ca` | `fd8a75195b33e5faaf1e13aae801c97485be5a3a65b40c28c34920b2b8a0ee18` | 1024×1024 |
| Green | Existing project synthetic watermarked clay prop | `040b71e3de49ae23dfcfed1387a56f32321acf61380a11cf5c6c5bb8a4ba2a73` | `d9e82709870c9c18b8e48c5c1477ca4db525447828799d3b0b612f74140a6911` | 1024×1024 |
| Control | Project-authored watermarked geometric non-target control | `1c51c348c0eab49d94959039de5816dbed8f4725c744271b0b34eb36cf75a9d0` | `9cb76c4d0bc72096e3dc08db468000d1db6a792542d6f1f5a2ec3ad940897fc7` | 1024×1024 |

The DEBUG lab rehashes the bytes loaded from its bundle before sanitization. Release excludes all three resources.

## Supporting automated evidence

- 14/14 host-core tests pass.
- 23/23 arm64 simulator app tests pass, including receipt round-trip, wrong-size/hash handling, explicit tamper rejection, descriptor path validation, durable/in-memory state separation, adapter and coordinator exclusive/stale-lease behavior, one-variable experiment enforcement, exact dominant-token parsing, fixture hash/dimension verification, evidence redaction, manual save during model preparation, persistence rollback, and stale-result timeout handling.
- Debug simulator build passes with bundle ID `com.omairmkhan.GITimeline.debug` and display name `GI Timeline Lab`.
- A fresh Release simulator build passes with unchanged bundle ID `com.omairmkhan.GITimeline`; no fixture files, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings are present in the built Release app.

Simulator results do not satisfy a physical gate.

## Required physical results

| Gate | Result |
|---|---|
| Signed isolated DEBUG launch | BLOCKED — Developer Mode disabled; no build/install attempted |
| Exact model download/import SHA-256 | NOT_RUN |
| Engine initialization/time | NOT_RUN |
| Dominant-color image consumption | NOT_RUN |
| Brown structured output | NOT_RUN |
| Green structured output | NOT_RUN |
| Brown repeatability | NOT_RUN |
| Non-target structured output | NOT_RUN |
| Five-run latency/stability | NOT_RUN |
| Peak/highest-observed memory | NOT_RUN |
| Airplane-Mode app-cold run with local cache | NOT_RUN |
| Review/correct/save/reopen/relaunch/delete | NOT_RUN |

## Next checkpoint

On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen, then stop. Codex will repeat read-only readiness and exact installed-bundle discovery; no app will be installed and no model will be downloaded without separate owner approval.
