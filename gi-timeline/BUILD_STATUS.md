# GI Timeline build status

> **Historical snapshot:** Device status in this file predates the final disclosed physical bridge. Use the repository root `README.md` and `DEVICE_INFERENCE_REPORT.md` for current claims.

Updated: 2026-08-01 14:40 EDT (America/New_York)

| Gate | Result |
| --- | --- |
| SwiftPM dependency | **PASS:** LiteRT-LM exact revision `f73637c57f0940b53da184e0d5adfc52a4e55eef` |
| Host tests | **PASS: 14/14** |
| Arm64 app tests | **PASS: 37/37** |
| Final exact-current UI suite | **PASS: 3/3** in 106.895 s |
| Optimized signed `GITimeline Hackathon` build | **PASS:** arm64, strict signature, isolated bundle ID |
| Exact embedded E4B | **PASS:** one copy, 3,659,530,240 bytes, pinned SHA-256, matching receipt |
| Optimized app size | **3,619,184 KiB** |
| Production configuration | **PASS:** `-O` whole-module, testability/debug dylib off, no fake/import/lab UI surface |
| Model failure shields | **PASS:** missing, wrong-size, and wrong-hash sources fail the build |
| Incremental verified reuse | **PASS** |
| Ordinary Release | **PASS:** arm64, production bundle ID, zero model files, no Hackathon/debug surface |
| Current embedded Simulator build/install | **PASS:** 43 s / 4 s |
| Current real-Gemma Simulator smoke | **PASS:** brown=`BROWN`, green=`GREEN`, control=`OTHER`, structured 3/3 |
| Current real-Gemma Simulator normal flow | **PASS:** automatic review, human edit, save, History, exact provenance |
| Current real-Gemma Simulator relaunch | **PASS:** entry, edit, image, and provenance reopened |
| Current optimized physical install/launch | **BLOCKED:** no physical iOS device visible to Xcode |
| Physical image inference/persistence | **BLOCKED** |
| Airplane Mode cold run | **BLOCKED** |

The signed build and an embedded model do not prove physical execution. See `TEST_RESULTS.md` for commands, `EMBEDDED_GEMMA_RESULTS.md` for exact evidence, and `DEVICE_INFERENCE_REPORT.md` for the physical boundary.
