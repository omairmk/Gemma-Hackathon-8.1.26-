# Attribution and synthetic-data notes

**PUBLICATION STATUS: BLOCKED.** This ledger is complete for the locally created fixtures, but the repository owner has not selected a repository license and third-party/model license notices have not been verified. Do not publish or redistribute model weights from this private handoff.

## Synthetic fixtures

Use only intentionally created, non-personal demonstration images. Watermark each image visibly with `SYNTHETIC`. Keep fixture provenance beside the asset:

| Asset | Source/creator | License/permission | Date created/acquired | Intended use | Contains real patient data? |
|---|---|---|---|---|---|
| `gi-timeline/Fixtures/synthetic-brown-clay.svg` | Project-authored SVG made from geometric primitives during this build preparation; no external media | Project-created; owner publication license not selected | 2026-07-31 | iPhone vision gate/demo | No — source is inspectable vector primitives and text only |
| `gi-timeline/Fixtures/synthetic-brown-clay.svg.png` | Locally rasterized from the adjacent project-authored SVG | Same as SVG source; owner publication license not selected | 2026-07-31 | iPhone vision gate/demo | No — derived only from the listed SVG |
| `gi-timeline/Fixtures/synthetic-green-clay.svg` | Project-authored SVG made from geometric primitives during this build preparation; no external media | Project-created; owner publication license not selected | 2026-07-31 | iPhone contrast gate/demo | No — source is inspectable vector primitives and text only |
| `gi-timeline/Fixtures/synthetic-green-clay.svg.png` | Locally rasterized from the adjacent project-authored SVG | Same as SVG source; owner publication license not selected | 2026-07-31 | iPhone contrast gate/demo | No — derived only from the listed SVG |
| `gi-journal/data/demo/synthetic_brown_clay_prop.png` | Generated locally by `gi-journal/scripts/make_fixtures.py` using Pillow drawing primitives; no external media | Project-created; owner publication license not selected | 2026-07-31 | Mac smoke/demo | No — generated from code and solid-color primitives only |
| `gi-journal/data/demo/synthetic_green_clay_prop.png` | Generated locally by `gi-journal/scripts/make_fixtures.py` using Pillow drawing primitives; no external media | Project-created; owner publication license not selected | 2026-07-31 | Mac contrast smoke/demo | No — generated from code and solid-color primitives only |

Do not label an image synthetic solely because it was edited, de-identified, or supplied without provenance. Do not commit real health images, EXIF/location-bearing photos, or user-entered journal data.

## Attribution ledger

| Component | Exact name/version | Source URL | License/required notice | Where credited |
|---|---|---|---|---|
| iPhone Gemma model | `litert-community/gemma-4-E4B-it-litert-lm`; exact artifact/hash not yet acquired | `https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm` | **BLOCKED — verify current Gemma/model-card terms; never commit or redistribute weights by assumption** | Pending README/Kaggle notice |
| Mac Gemma models | `mlx-community/gemma-4-e4b-it-4bit` @ `475b9088d29754a3379866cf5aeb6b41acd313c2`; `mlx-community/gemma-4-e2b-it-4bit` @ `238767527555cb75a05732a84dff5d6ba0dd6809` | `https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit`; `https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit` | **BLOCKED — verify current Gemma/model-card terms; local snapshots are excluded from Git/archive** | Pending README/Kaggle notice |
| iPhone runtime | LiteRT-LM `v0.14.0`, commit `80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6` | `https://github.com/google-ai-edge/LiteRT-LM` | **BLOCKED — verify and reproduce upstream license/notice before publication** | Pending NOTICE/README |
| Mac runtime | `mlx-vlm==0.6.8` plus direct versions in `gi-journal/requirements.txt` | `https://github.com/Blaizzy/mlx-vlm` | **BLOCKED — verify runtime and transitive dependency notices before publication** | Pending NOTICE/README |
| Apple frameworks and UI media | SwiftUI, SwiftData, PhotosUI, SF Symbols/system fonts | Apple SDK/framework documentation | **BLOCKED — owner/publication review of applicable Apple terms; no third-party media is bundled** | Pending README |

Before publication, add an owner-selected top-level `LICENSE`, assemble a verified third-party `NOTICE`, remove private organizer form links and personal/local identifiers from a public copy, and verify the event’s current attribution language and model/runtime licenses. Never assume model weights may be redistributed: link to official acquisition instructions unless permission is explicit.

## Claim-control notes

Describe only what the completed build and saved evidence show. “Local,” “offline,” and “on-device” are separate claims; each needs its own verification. Privacy language must state actual design limits, including platform backup behavior where applicable. Keep medical framing documentation-only: no diagnosis, cause, treatment, prognosis, risk scoring, or reassurance.
