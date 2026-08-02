# Final inference handoff pointer

This file supersedes the July 31 pre-model planning snapshot.

Use the repository root `README.md` and `DEVICE_INFERENCE_REPORT.md` for the current evidence-backed status. `MORNING_HANDOFF.md` and `EMBEDDED_GEMMA_RESULTS.md` retain timestamped historical evidence.

Current boundary:

- `REAL_GEMMA_BACKEND: SIMULATOR_LOCAL`
- `REAL_GEMMA_E2E: PASS`
- `NORMAL_APP_FLOW: PASS`
- `UI_ACCEPTANCE: PASS`
- `PHYSICAL_GEMMA_IMAGE_INFERENCE: BLOCKED`
- `OFFLINE_IPHONE: BLOCKED`
- `MORNING_LABEL: SIMULATOR_GEMMA_POC_GO`

The proven model is Gemma 4 E4B (`litert-community/gemma-4-E4B-it-litert-lm`, revision `28299f30ee4d43294517a4ac93abd6163412f07f`, SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`). Simulator evidence must not be represented as physical-iPhone or offline-iPhone evidence.
