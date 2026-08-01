# Operator iPhone checkpoint

`DEVICE_INFERENCE_STATUS: BLOCKED`

The physical iPhone is now visible, paired, and listed by Xcode. CoreDevice stopped the exact installed-app check with error `10005` because Developer Mode is disabled, so no signed build, model download, model import, engine initialization, image request, or physical acceptance gate has run.

## One action now

- [ ] On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, tap **Restart**, then after restart swipe up, tap **Enable** in the confirmation, and enter the device passcode only on the iPhone. Leave it unlocked on the Home Screen, then stop.

Expected result: Developer Mode shows on and the phone is unlocked on the Home Screen. If the option or confirmation is missing, stop and return the exact visible text or a screenshot with personal notifications hidden.

This action authorizes only a repeat of read-only readiness and exact installed-bundle discovery. It does **not** authorize signing changes, app installation, model-terms acceptance, a multi-gigabyte download, model import, inference, Airplane Mode, or deletion.

## State waiting behind this checkpoint

| Item | Current state |
|---|---|
| Physical destination | Visible: wired, paired, booted iPhone 17 Pro Max on iOS 26.5.2; Xcode lists an arm64 destination. Build remains `BLOCKED` on Developer Mode. |
| Existing GI Timeline installation | UNKNOWN — exact production/debug bundle queries were refused before results because Developer Mode is disabled |
| Supporting tests | PASS: 14/14 host-core at 15:38 ET and 23/23 current-source arm64 iPhone 17 Pro simulator tests at 15:37 ET on 2026-07-31; neither is physical evidence |
| Isolated Debug bundle | Simulator-built only: `com.omairmkhan.GITimeline.debug`, display name `GI Timeline Lab`; contains the DEBUG-only lab, three synthetic fixtures, and probe path |
| Release bundle | Simulator-built only: `com.omairmkhan.GITimeline`, display name `GI Timeline`; fresh built-Release inspection found no lab fixtures, lab title, probe prompt, evidence-directory string, or DEBUG candidate descriptor strings |
| Planned first baseline | Descriptor only: `google/gemma-3n-E2B-it-litert-lm` at `73b019b63436d346f68dd9c1dbfd117eb264d888`; `gemma-3n-E2B-it-int4.litertlm`; 3,388,604,416 bytes; SHA-256 `6c5f6d8f727e3f4327dbe38731c92c47094a95fccee9c15484465e7d9e01e4d5`; absent, not downloaded, not owner-accepted, and not physically selected |
| Compiled configuration | LiteRT-LM `f73637c57f0940b53da184e0d5adfc52a4e55eef`; `.gpu`; vision `.cpu()`; `maxNumTokens=2048`; `topK=1`; `topP=1`; temperature `0`; seed `0`; prompt `gi-observation-v1`; image plus text; never physically run |
| Selection record | `SELECTED_MODEL.json` intentionally absent |
| Physical inference | `NOT_RUN` |
| Normal-app end to end | `NOT_RUN` |

After the single action above, Codex will repeat read-only readiness and exact installed-bundle discovery and report what the Mac sees before requesting any separate authorization.
