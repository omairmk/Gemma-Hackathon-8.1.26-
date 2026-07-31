# GI Hackathon Operator Queue

Updated: 2026-07-31 10:04 EDT. Work through this list in order. Tell Codex when an item is complete and include any exact message, screenshot, or observed result.

## 0. Accept the Xcode license

- WHAT: Open Terminal and run `sudo xcodebuild -license`, read/scroll as prompted, type `agree`, then run `xcodebuild -version` and paste the output back here.
- GUIDE: `assets/OPERATOR_GUIDES.md` §3, “Accept the Xcode license.”
- WHY: `xcodebuild` and `swift` are currently blocked before any Track A compile or test can run.
- TIME: 3-5 minutes.
- STATUS: **BLOCKING — NOT STARTED.** Detected 2026-07-31 10:04 EDT.

## 1. Ask the event starter-code question

- WHAT: Post this verbatim in the event Discord: "Are teams allowed to arrive with a custom Swift starter app that already performs local image inference and includes basic persistence and test scaffolding, or may we only preinstall tools, dependencies, and model files?"
- GUIDE: `assets/OPERATOR_GUIDES.md` §1, “Starter-code rules question.”
- WHY: The answer sets `STARTER_CODE_ALLOWED`; NO or unanswered means the Saturday iPhone build is off and the Mac fallback is used.
- TIME: 2 minutes plus response time.
- STATUS: **NOT STARTED.**

## 2. Complete Friday event forms

- WHAT: From the organizer's latest Friday message, submit the [One WTC security-list form](https://forms.gle/bt7woPmo48GnQ1tw7) before **12:00 PM EDT today**, using your full legal name exactly as shown on government photo ID. Submit the [Cerebras credits form](https://forms.gle/6i9a32hUhfWa2aQ68) before **8:00 PM EDT today**. Save confirmation screenshots; Google Forms may not email a receipt. If you already submitted, verify before submitting a duplicate.
- GUIDE: `assets/OPERATOR_GUIDES.md` §2, “Building access and Cerebras forms.”
- WHY: Event access and credits; this does not change either code gate.
- TIME: 5-10 minutes.
- STATUS: **TIME-SENSITIVE — COMPLETION UNVERIFIED.** Gmail shows a Luma ticket reminder at 10:01 EDT but no form receipt; lack of a receipt is not proof of non-submission.

## 3. Connect, trust, sign, and install on the iPhone

- WHAT: Connect the newest Pro Max by cable, trust the Mac, select the phone as the Xcode run destination, choose the signing team, preserve the staging bundle ID, and approve the first build to device.
- GUIDE: `assets/OPERATOR_GUIDES.md` §4, “Connect, trust, sign, and first-build the iPhone.”
- WHY: Unblocks all physical Track A gates.
- TIME: 10-20 minutes.
- STATUS: **BLOCKED on Track A project plus item 0.**

## 4. Install AI Edge Gallery and run Ask Image

- WHAT: Install AI Edge Gallery from the App Store; use Ask Image with Gemma 4 on the supplied brown watermarked synthetic prop; record exact result and latency.
- GUIDE: `assets/OPERATOR_GUIDES.md` §5, “AI Edge Gallery viability check.”
- WHY: Adds independent device-viability evidence; it is not app-source evidence.
- TIME: 10-20 minutes plus any model download.
- STATUS: **NOT STARTED.**

## 5. Transfer and import the E4B model

- WHAT: Finder-transfer the verified multimodal E4B artifact to the app's `Documents/Import/`, tap the in-app import, and record the verified-hash banner. Do not use a `-web` text-only artifact.
- GUIDE: `assets/OPERATOR_GUIDES.md` §6, “Import verified E4B model.”
- WHY: Unblocks engine bring-up and image inference.
- TIME: 10-30 minutes depending on transfer speed.
- STATUS: **BLOCKED on model download/hash and device install.**

## 6. Run the guided physical gate session

- WHAT: Run brown-vs-green vision checks, the repeated-brown consistency check, five consecutive analyses, warm latency/memory recording, SwiftData CRUD/draft lifecycle, Airplane Mode force-quit/cold relaunch, and the Mac fallback Wi-Fi-off restart check.
- GUIDE: `assets/OPERATOR_GUIDES.md` §§7–8, “Physical iPhone gate session” and “Mac Wi-Fi-off check.”
- WHY: Supplies the evidence required to set `MOBILE_PRECHECK.md` and `PRECHECK.md`; an honest NO-GO is acceptable.
- TIME: 35-50 minutes.
- STATUS: **BLOCKED on items 3-5 and agent-side preflight work.**

## Recovered inputs

- The frozen `GI_Journal_Preflight_Prompt_v3_2_1.md` and `GI_Journal_Build_Prompt_v3_2_1.md` were recovered from their exact source artifacts at 10:12 EDT and staged in `gi-journal/`. No operator action is needed for these files.
