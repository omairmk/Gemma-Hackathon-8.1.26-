# Physical iPhone inference report

Updated: 2026-08-01 14:25 EDT (America/New_York)

## Verdict

Real Gemma image inference on the physical iPhone is **not yet proven**.

```text
DEVICE_INFERENCE_STATUS: BLOCKED
APP_END_TO_END_STATUS: NOT_RUN
```

Those legacy fields retain their original physical/offline meaning and are not upgraded by Simulator evidence.

## What is verified

- The current `GITimeline Hackathon` source produces an optimized, signed arm64 app with bundle ID `com.omairmkhan.GITimeline.debug`.
- Strict signature verification passes.
- The bundle contains exactly one pinned E4B artifact at `EmbeddedModels/gemma-4-E4B-it.litertlm`.
- Bundled bytes and SHA-256 match the retained ignored source and the verification receipt.
- The optimized app is 3,619,184 KiB.
- An earlier embedded build installed on the intended phone without uninstalling or deleting app data. That historical install does not prove the current optimized artifact or any inference gate.
- Host tests pass 14/14, app tests pass 37/37, the native UI suite passes 3/3, and the model-free Release build passes.

## Current blocker

A fresh sanitized Xcode device query returned no physical iOS devices. Therefore the current optimized app could not be installed or launched, and none of the following is claimed:

- physical engine initialization;
- brown/green/control content dependence;
- structured physical image output;
- reviewed save, History, terminate/relaunch, or reopen on the phone;
- physical latency, memory, or stability;
- Airplane Mode cold launch or offline operation.

## Prepared physical configuration

| Field | Value |
| --- | --- |
| Model | `litert-community/gemma-4-E4B-it-litert-lm` |
| Artifact revision | `28299f30ee4d43294517a4ac93abd6163412f07f` |
| LiteRT-LM revision | `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Engine / vision backend | GPU / CPU (non-nil) |
| Physical visual-token graph | `vision_70` (`visualTokenBudget=70`) |
| Generation context capacity | 1024 |
| Sampler | `topK=1`, `topP=1`, temperature `0`, seed `0` |
| Prompt | `gi-observation-v1` |
| Request | sanitized image file plus text prompt |

## One owner action

Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. The visible success condition is that it appears as available in Xcode without an Unlock, Trust, Developer Mode, or developer-profile prompt.

Once visible, install the already-verified optimized artifact without uninstalling, run the bounded synthetic brown/green/control harness, complete one reviewed save/History/relaunch sequence, and only then request the separate Airplane Mode action.
