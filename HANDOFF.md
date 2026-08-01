# GI Timeline public team handoff

Updated: 2026-08-01 (America/New_York)

This branch is the public hackathon proof-of-concept source for GI Timeline. It is a prototype, not medical advice or a diagnostic tool. Human review remains required before save.

## What works

- Real Gemma 4 E4B image-plus-text inference passes in an arm64 iPhone Simulator.
- Synthetic brown, green, and geometric-control pixels produce distinct `BROWN`, `GREEN`, and `OTHER` results.
- The normal photo → automatic analysis → editable review → save → History → relaunch flow passes.
- The dedicated Hackathon configuration can embed the pinned model at build time; ordinary Release remains model-free.
- Current native screenshots and accessibility evidence are under `gi-timeline/outputs/demo-screens/native-*`.

## Exact model

- Model: `litert-community/gemma-4-E4B-it-litert-lm`
- Revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact: `gemma-4-E4B-it.litertlm`
- Bytes: `3,659,530,240`
- SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- LiteRT-LM revision: `f73637c57f0940b53da184e0d5adfc52a4e55eef`

The large model is intentionally excluded from normal Git history. The companion GitHub prerelease contains a complete ad-hoc-signed arm64 Simulator app split into sub-2-GiB assets, with reconstruction instructions, checksums, Apache-2.0 text, and third-party notices.

## Honest boundary

`SIMULATOR_GEMMA_POC_GO` is proven. Physical-iPhone Gemma inference and Airplane-Mode operation remain blocked/not run and are not claimed. Deterministic UI-test providers prove interface behavior only; they are not real-Gemma evidence.

Start with:

- `gi-timeline/README.md`
- `gi-timeline/MORNING_HANDOFF.md`
- `gi-timeline/DEMO_RUNBOOK.md`
- `gi-timeline/TEST_RESULTS.md`
- `gi-timeline/EMBEDDED_GEMMA_RESULTS.md`

## Sharing and licensing

This source is shared for the owner's hackathon-team collaboration. No repository-wide license grant is asserted by this handoff. Third-party code and model artifacts retain their respective licenses; preserve the supplied Apache-2.0 text and notices when redistributing the packaged model build.
