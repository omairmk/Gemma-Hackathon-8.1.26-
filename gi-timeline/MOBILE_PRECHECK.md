> **Historical snapshot:** This precheck predates the final disclosed physical bridge. Use the repository root `README.md` and `DEVICE_INFERENCE_REPORT.md` for current claims.

STARTER_CODE_ALLOWED:
STATUS:
EVENT_STARTER_CODE_ALLOWED: UNANSWERED
DEVICE_INFERENCE_STATUS: BLOCKED
APP_END_TO_END_STATUS: NOT_RUN

# GI Timeline mobile precheck

Updated: 2026-08-01 14:25 EDT (America/New_York)

The two legacy status fields above still require physical-iPhone image inference and the original device acceptance gates. They are intentionally not upgraded by a signed build, embedded model, Simulator run, or UI test.

## Current precheck

| Gate | Result |
| --- | --- |
| Exact E4B source | **PASS:** 3,659,530,240 bytes and pinned SHA-256 |
| LiteRT-LM dependency | **PASS:** exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Host tests | **PASS: 14/14** |
| Arm64 app tests | **PASS: 37/37** |
| Native UI tests | **PASS: 3/3**, plus focused dark/AXXL checks |
| Signed optimized Hackathon build | **PASS:** arm64, strict signature, isolated bundle ID |
| Embedded model identity | **PASS:** exactly one verified model and matching receipt |
| Ordinary Release isolation | **PASS:** model-free and no Hackathon/debug surface |
| Physical device visibility | **BLOCKED:** fresh sanitized Xcode query returned no physical iOS device |
| Current optimized physical install/launch | **BLOCKED** |
| Physical brown/green/control inference | **BLOCKED** |
| Physical review/save/History/relaunch | **BLOCKED** |
| Airplane Mode cold launch | **BLOCKED** |

## Current artifact

- Scheme/configuration: `GITimeline Hackathon` / `Hackathon`
- Bundle ID: `com.omairmkhan.GITimeline.debug`
- Architecture: arm64
- App size: 3,619,184 KiB
- Model: `litert-community/gemma-4-E4B-it-litert-lm`
- Model revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- Model path in bundle: `EmbeddedModels/gemma-4-E4B-it.litertlm`
- Model SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- Physical backend policy: GPU engine / non-nil CPU vision
- Simulator exception: CPU engine / CPU vision

Signing values, device identifiers, model weights, result bundles, and private logs are deliberately omitted.

## One next operator action

Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen. Stop when it appears as available in Xcode without any owner prompt. No credential or device identifier should be sent to Codex.
