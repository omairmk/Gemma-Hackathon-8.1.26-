# [PROJECT NAME] — Kaggle submission draft

**Submission status:** Draft. Replace bracketed fields only with evidence collected during the event. Delete any option that did not run. Do not describe planned, simulated, or unverified results as completed work.

## Problem

People documenting gastrointestinal symptoms can benefit from a reviewable record to discuss with a clinician. **[PROJECT NAME]** is a documentation tool: it does not diagnose, identify causes, recommend treatment, assess risk, or offer reassurance. Privacy/deployment claim, if verified: **[exact evidence-backed wording, or delete]**.

## What we built

Choose exactly one completed implementation:

- **iPhone build — GITimeline:** A native SwiftUI + SwiftData journal that **[describe only functions actually demonstrated; add local/on-device wording only with recorded device evidence]**.
- **Mac fallback — GI Journal:** A Mac application that **[describe only functions actually demonstrated; add local/offline wording only with recorded socket and Wi-Fi-off evidence]**.

Evidence captured during the event: **[build/test log path]**, **[offline demo evidence]**, **[model/version/hash evidence]**.

## Core Gemma 4 usage

The completed build used **[exact Gemma 4 artifact/model identifier, only after model/hash verification]** for **[exact verified use and processing location]**. Verified output contract: **[structured neutral fields / validation / human correction—retain only what the completed build demonstrated]**.

Do not claim “on-device,” “offline,” “Gemma 4,” “vision,” “private,” or a model size unless the corresponding recorded evidence is available.

## Architecture and privacy

- Processing location actually demonstrated: **[iPhone / Mac / other — only if verified]**.
- Data storage actually demonstrated: **[local storage implementation]**.
- Networking behavior actually tested: **[test and result, or “not tested”]**.
- Human review: **[how an operator edited/acknowledged observations]**.
- Backup behavior: **[state documented platform behavior; do not claim no backup without proof]**.

For the iPhone build, use this exact qualifier only after verifying it matches the final app and architecture evidence: “The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings.” Otherwise write **[privacy/backup behavior not claimed]**.

## Challenges and what we learned

- **[challenge observed, e.g. local runtime integration]** → **[evidence-backed resolution or remaining limitation]**.
- **[challenge observed]** → **[resolution/limitation]**.

## Responsible use and limitations

Outputs are neutral observations, not medical conclusions. Images may be unclear and visual appearance can vary with lighting and camera processing. The user remains in control of corrections and saved records. **[Add only limitations directly observed or specified by the finished build.]**

## Reproducibility

- Repository: **[public repository URL, if made public]**
- Commit/tag: **[immutable revision]**
- Setup instructions: **[link/path]**
- Demo media: **[link/path, with only permitted synthetic or consented material]**

## Team and acknowledgments

- Team: **[names/roles]**
- Gemma/model/runtime attribution: **[exact required attribution from event and model documentation]**
- Synthetic fixture attribution: **[link to attribution note]**
