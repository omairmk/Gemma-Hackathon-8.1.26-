# Attribution and synthetic-data notes

## Synthetic fixtures

All committed demo images are intentionally created, non-personal fixtures. They contain no real patient data, personal photo, GPS/EXIF identity, account identifier, or notification content.

| Asset family | Source | Intended use |
| --- | --- | --- |
| `gi-timeline/Fixtures/synthetic-*.svg` and `.png` | Project-authored geometric/vector fixtures and adjacent rasterizations | iOS image-dependence tests and demo |
| `gi-journal/data/demo/synthetic_*_clay_prop.png` | Generated locally by `gi-journal/scripts/make_fixtures.py` from drawing primitives | Mac fallback smoke tests |
| `gi-timeline/outputs/demo-screens/native-*` | Sanitized Simulator captures using synthetic fixture data | Current native UI evidence |

Do not commit real health images, user-entered journal data, or photos containing identifying metadata.

## Model and runtime attribution

| Component | Exact identity | License / distribution note |
| --- | --- | --- |
| Embedded iOS model | `litert-community/gemma-4-E4B-it-litert-lm`; revision `28299f30ee4d43294517a4ac93abd6163412f07f`; SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | Gemma 4 is distributed under Apache-2.0. The team package includes the license text and notices. |
| iOS runtime | LiteRT-LM commit `f73637c57f0940b53da184e0d5adfc52a4e55eef` | Apache-2.0 upstream project; preserve its license and notices. |
| Mac fallback candidates | `mlx-community/gemma-4-e4b-it-4bit` and `gemma-4-e2b-it-4bit` at revisions recorded in `gi-journal/PRECHECK.md` | Not bundled in the iOS team package or Git history. Consult their model cards before separate redistribution. |
| Apple frameworks | SwiftUI, SwiftData, PhotosUI, and system UI assets | Supplied by the Apple SDK; no third-party photo media is bundled. |

The normal Git tree deliberately excludes model weights. The companion split GitHub prerelease is the only package in this project that contains the exact embedded E4B artifact, together with `LICENSE-APACHE-2.0.txt`, `THIRD_PARTY_NOTICES.md`, and `SHA256SUMS.txt`.

## Claim boundary

The saved evidence proves local Gemma image inference in an arm64 iPhone Simulator and the normal editable review/save/History/relaunch flow. It does not prove physical-iPhone inference or Airplane-Mode operation. The app is a prototype and not medical advice or diagnosis.
