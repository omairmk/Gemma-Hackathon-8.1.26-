# GI Journal third-party notices

Status: **draft for the current manual-fallback public lane; not final legal approval**.
Updated: 2026-09-01.

The current public AppStore lane does not bundle a third-party model, inference runtime, native AI framework, or third-party SDK. `ThirdPartyNotices.txt` in the built app states that no third-party model or inference runtime is bundled.

Apple-provided SDK and operating-system frameworks are used by the app for UI, persistence, camera/photo attachment, PDF generation, image/file handling, and cryptographic hashes. Those platform components are supplied under Apple's developer and platform terms, not bundled as third-party application packages by this repository.

## Current public payload

Required release validators must reject any of the following in the production archive or exported IPA:

- `EmbeddedModels` directories or model receipts.
- `.litertlm`, `.safetensors`, `.gguf`, or similar model files.
- LiteRT, Gemma, Qwen, MLX, or CLiteRT-named payloads.
- Debug, Hackathon, physical-qualification, synthetic-evaluation, or XCTest resources.

## Historical and internal materials

Earlier GI Journal development explored Gemma, Qwen, LiteRT-LM, CLiteRTLM, MLX, and synthetic-evaluation pipelines. Those records are historical/internal evidence only. They do not describe the current public manual-fallback AppStore bundle, are not user-facing App Review copy, and are not shipping third-party payload notices for this branch.

If a future AI-enabled or third-party-runtime branch is admitted, do not amend this manual-fallback notice by implication. Create a new source-bound notice packet that retrieves the then-current license text, model card, use policy, binary/framework notices, transitive obligations, and legal approval for the exact submitted artifact.

## Operator/legal status

- **[LEGAL — BLOCKING]** Confirm whether any final non-AI third-party notices are required for the exact signed archive and public legal surface.
- **[RELEASE ENGINEERING — BLOCKING]** Re-run archive/IPA inventory and attach the final bundle file list.
- **[CONDITIONAL — FUTURE AI BRANCH ONLY]** Review and approve all model/runtime licenses, notices, redistribution rights, use policies, territory limits, and product claims before any AI-enabled public admission.
