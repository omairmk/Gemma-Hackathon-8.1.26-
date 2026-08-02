# Physical iPhone inference report

Updated: 2026-08-01 16:06 EDT (America/New_York)

## Verdict

Real raw-image Gemma inference on the physical iPhone is **not yet proven**. A disclosed, crash-avoiding hackathon bridge is now physically proven.

```text
DEVICE_INFERENCE_STATUS: BLOCKED
APP_END_TO_END_STATUS: NOT_RUN
```

Those legacy fields retain their original raw-multimodal/offline meaning. The separate bridge result is:

```text
PHYSICAL_HACKATHON_BRIDGE_STATUS: PASS
BRIDGE_APP_END_TO_END_STATUS: PASS
```

The installed app did not embed a Git revision, and the retained install records do not preserve a matching binary hash. The published bridge source is therefore a reproducible implementation of the documented behavior, not a claim of byte-for-byte identity with the installed phone binary.

## What is verified

- The current `GITimeline Hackathon` source produces an optimized, signed arm64 app with bundle ID `com.omairmkhan.GITimeline.debug`.
- Strict signature verification passes.
- The bundle contains exactly one pinned E4B artifact at `EmbeddedModels/gemma-4-E4B-it.litertlm`.
- Bundled bytes and SHA-256 match the retained ignored source and the verification receipt.
- The exact E4B text engine initializes and generates on the intended physical iPhone with a 2,048-token CPU configuration and no vision executor.
- The phone creates a bounded local 12x12 color/shape map, sends only those measurements to embedded Gemma, and clearly discloses that Gemma did not receive the raw image.
- Physical normal flow produced an original Bristol Type 4 / brown / smooth-formed suggestion, reached editable review, persisted a human edit, saved the image and record to History, and passed terminate/relaunch verification.
- Host tests pass 14/14 and app tests pass 41/41.

## Remaining blocker

LiteRT-LM 0.14 fails inside the exact E4B vision executor on the physical phone across CPU/GPU backend combinations and the model's 70-token vision graph. Direct raw-image multimodal inference therefore remains blocked by the packaged native runtime. Airplane Mode cold-launch acceptance is also still unrun.

## Prepared physical configuration

| Field | Value |
| --- | --- |
| Model | `litert-community/gemma-4-E4B-it-litert-lm` |
| Artifact revision | `28299f30ee4d43294517a4ac93abd6163412f07f` |
| LiteRT-LM revision | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Engine / vision backend | CPU / disabled for the physical bridge |
| Context capacity | 2048 |
| Sampler | `topK=1`, `topP=1`, temperature `0`, seed `0` |
| Prompt | `gi-local-pixel-bridge-v1` |
| Request | bounded local pixel-facts JSON plus text prompt; no raw image to Gemma |

## Next acceptance action

Run the app with a synthetic or publicly licensed fixture and manually review all five fields. Treat Bristol/form/color as low-confidence hackathon suggestions. A later native LiteRT fix is still required before changing the legacy raw-image status fields.
