# GI Hackathon Operator Queue

**PRIVATE OPERATOR HANDOFF:** this file contains organizer-provided intake links. Do not publish it; create a sanitized public copy first.

Updated: 2026-07-31 12:42 EDT. Work through this list in order. Tell Codex when an item is complete and include any exact message, screenshot, or observed result.

## 0. Accept the Xcode license

- WHAT: Open Terminal and run `sudo xcodebuild -license`, read/scroll as prompted, type `agree`, then run `xcodebuild -version` and paste the output back here.
- GUIDE: `assets/OPERATOR_GUIDES.md` §3, “Accept the Xcode license.”
- WHY: Cleared the local Xcode/Swift toolchain gate used for the completed Mac and simulator checks.
- TIME: 3-5 minutes.
- STATUS: **DONE.** Rechecked 2026-07-31 10:22 EDT: `xcodebuild -version` and `swift --version` both succeed.

## 1. Ask the event starter-code question

- WHAT: Post this verbatim in the event Discord: "Are teams allowed to arrive with a custom Swift starter app that already performs local image inference and includes basic persistence and test scaffolding, or may we only preinstall tools, dependencies, and model files?"
- GUIDE: `assets/OPERATOR_GUIDES.md` §1, “Starter-code rules question.”
- WHY: The answer sets `STARTER_CODE_ALLOWED`; NO or unanswered means the Saturday iPhone build is off and the Mac fallback is used.
- TIME: 2 minutes plus response time.
- STATUS: **NOT STARTED.**

## 2. Complete Friday event forms

- WHAT: The One WTC deadline has passed and completion is unverified. Open the [One WTC security-list form](https://forms.gle/bt7woPmo48GnQ1tw7) and capture any existing response/confirmation. If it is closed or confirmation cannot be established, capture that page and contact the organizer immediately; do not submit a duplicate or claim that an earlier submission was missed. Submit the [Cerebras credits form](https://forms.gle/6i9a32hUhfWa2aQ68) before **8:00 PM EDT today** and save its confirmation; Google Forms may not email a receipt.
- GUIDE: `assets/OPERATOR_GUIDES.md` §2, “Building access and Cerebras forms.”
- WHY: Event access and credits; this does not change either code gate.
- TIME: 5-10 minutes.
- STATUS: **ONE WTC DEADLINE PASSED; COMPLETION UNVERIFIED. CEREBRAS TIME-SENSITIVE.** Gmail shows a Luma ticket reminder at 10:01 EDT but no form receipt; lack of a receipt is not proof of non-submission.

## 3. Connect, trust, sign, and install on the iPhone

- WHAT: Connect the newest Pro Max by cable, trust the Mac, select the phone as the Xcode run destination, choose the signing team, preserve the staging bundle ID, and approve the first build to device.
- GUIDE: `assets/OPERATOR_GUIDES.md` §4, “Connect, trust, sign, and first-build the iPhone.”
- WHY: Unblocks all physical Track A gates.
- TIME: 10-20 minutes.
- STATUS: **BLOCKED on item 1 and the upstream LiteRT-LM v0.14.0 checksum mismatch.** A non-committed checksum-corrected arm64 simulator overlay builds and passes 11/11 app-target tests, but the frozen exact remote pin still fails resolution. Do not silently repin; a later correction commit would require explicit authorization.

## 4. Install AI Edge Gallery and run Ask Image

- WHAT: Install AI Edge Gallery from the App Store; use Ask Image with Gemma 4 on the supplied brown watermarked synthetic prop; record exact result and latency.
- GUIDE: `assets/OPERATOR_GUIDES.md` §5, “AI Edge Gallery viability check.”
- WHY: Adds independent device-viability evidence; it is not app-source evidence.
- TIME: 10-20 minutes plus any model download.
- STATUS: **NOT STARTED.**

## 5. Transfer and import the E4B model

- WHAT: **Operator/auth step first:** open the official `litert-community/gemma-4-E4B-it-litert-lm` model page, accept any current terms/sign-in required by the provider, obtain the exact non-`-web` multimodal `.litertlm` artifact, and send Codex its local path plus `shasum -a 256` output. **Codex then:** validates the artifact identity/hash and records it in `MOBILE_PRECHECK.md`. Only after that, Finder-transfer the verified artifact to the app's `Documents/Import/`, tap the in-app import, and record the verified-hash banner. Never substitute a `-web` text-only artifact.
- GUIDE: `assets/OPERATOR_GUIDES.md` §6, “Import verified E4B model.”
- WHY: Unblocks engine bring-up and image inference.
- TIME: 10-30 minutes depending on transfer speed.
- STATUS: **BLOCKED on model download/hash and device install.**

## 6. Run the guided physical gate session

- WHAT: Run brown-vs-green vision checks, the repeated-brown consistency check, five consecutive analyses, warm latency/memory recording, SwiftData CRUD/draft lifecycle, and Airplane Mode force-quit/cold relaunch. For the Mac fallback, keep Wi-Fi on while running the mandatory full E4B smoke and candidate attempt on port 8080, safely revalidate/stop its exact PID, then run the mandatory full E2B smoke and candidate attempt on port 8080 with its own evidence file. Select only by the frozen eligible-E4B-at-≤60-seconds-otherwise-eligible-E2B rule, then run one selected-candidate offline command.
- GUIDE: `assets/OPERATOR_GUIDES.md` §§7–8, “Physical iPhone gate session” and “Mac dual-model qualification and one-command Wi-Fi-off check.”
- WHY: Supplies the evidence required to set `MOBILE_PRECHECK.md` and `PRECHECK.md`; an honest NO-GO is acceptable.
- TIME: 35-50 minutes for the phone session; 20-35 minutes for the Mac sequence.
- STATUS: **PARTIALLY READY.** The iPhone portion is blocked on items 3-5. Track B has 33 passing tests but remains `STATUS: NO-GO`: both model attempts failed before binding because this sandbox has no Metal device. The copyable physical-Mac sequence is in `assets/OPERATOR_GUIDES.md` §8. Wi-Fi remains on through both distinct `smoke_evidence_e4b.json` / `smoke_evidence_e2b.json` runs and candidate creation. Never infer eligibility. Only `scripts/offline_test.sh` for the selected revalidated candidate turns Wi-Fi off; it prints PASS only after verified restoration.

## Recovered inputs

- The frozen `GI_Journal_Preflight_Prompt_v3_2_1.md` and `GI_Journal_Build_Prompt_v3_2_1.md` were recovered from their exact source artifacts at 10:12 EDT and staged in `gi-journal/`. No operator action is needed for these files.
