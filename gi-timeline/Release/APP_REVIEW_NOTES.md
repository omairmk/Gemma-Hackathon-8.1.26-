# GI Journal App Review notes

> **Current release direction — 2026-08-30:** The public `MANUAL_FALLBACK_RELEASE` build keeps photos as local manual-entry attachments, contains no model payload, and does not expose photo analysis, model repair, or prefill. Historical candidate evidence remains internal and does not qualify or describe this public route. **DO NOT SUBMIT** until the manual fallback passes its exact-build gates and every blocker and placeholder below is closed.

> **Submission draft — 2026-08-02:** These notes describe the intended AppStore build. The release operator must verify every statement against the uploaded binary and replace every placeholder.

## Review contact

- Contact: **[APP REVIEW CONTACT NAME]**
- Email: **[APP REVIEW CONTACT EMAIL]**
- Phone: **[APP REVIEW CONTACT PHONE]**
- Support URL: **[PUBLIC HTTPS SUPPORT URL]**
- Privacy URL: **[PUBLIC HTTPS PRIVACY URL]**

## Access and payment

GI Journal has no account, sign-in, activation, demo credential, or developer-server dependency. It is a paid-upfront app. The App Store purchase provides the complete feature set; the app contains no in-app purchases, subscriptions, trials, or additional paywalls.

## What the app does

GI Journal is a private documentation tool for user-reviewed digestive-health observations. The public interface has three tabs: **Log**, **Journal**, and **Settings**. A person can:

- create a manual entry with no photo;
- take or choose a photo as an attachment to a manual entry; the public fallback does not analyze it or prefill fields;
- enter and edit the complete observation, symptoms, and context, then save the whole entry once;
- record a dated day with no bowel movement;
- save, reopen, edit, delete, or bookmark local entries for discussion;
- create, preview, and share a date-bounded PDF that includes every attached photo for selected entries; if any expected attached photo cannot be verified, no PDF is created.

The app does not diagnose, classify a disease or its severity, recommend treatment, or provide individualized or professional medical advice. The person enters and reviews the complete entry before saving. **[LEGAL/REGULATORY — BLOCKING]** Approve the final intended-use wording and classification before submission.

## Suggested review path

No credentials are needed.

1. Launch the app and tap **Continue** on the first-run explanation.
2. On **Log**, choose **Enter details without a photo**.
3. Complete the entry, optionally add context, and use **Save entry** once.
4. Open **Journal** and open the saved entry.
5. Use **Edit entry** to change an entry field, save the change, and reopen it.
6. Return to **Log**, choose **Record no bowel movement**, select a date, and save the dated marker. Confirm that it appears in Journal.
7. From **Journal**, choose **Export PDF**, select an inclusive range and All or Marked, preview the PDF, then dismiss or share it.
8. Exercise the optional photo path with a non-sensitive test image. Confirm that the photo is attached to the complete manual sheet, no analysis or prefill is offered, and **Save entry** saves it with the entry.
9. Close and relaunch the app to exercise expected same-install retention behavior. **[OPERATOR — BLOCKING]** Separately qualify the exact Apple-processed build through a physical restart/unlock and a signed in-place update before submission.

If Camera access is declined, the system Photos picker and no-photo paths remain available. The picker gives the app only the selected item and can be cancelled; it does not require broad Photo Library authorization. If an item exists only in iCloud, Apple Photos may need to download it before GI Journal can attach its local copy. If no image is selected, the no-photo path remains available.

## Model-free public photo path

The public App Store bundle contains no model payload. `MANUAL_FALLBACK_RELEASE` makes every model selector unavailable, and the public interface does not prepare, analyze, repair, or prefill a photo. Internal model experiments remain non-public implementation history and do not describe this configuration. Do not describe model inference as a shipping feature.

**[OPERATOR — BLOCKING]** Verify that the exact uploaded model-free build remains within current App Store limits and that download/install messaging and device availability match the final support matrix.

## Privacy and networking

- No account or sign-in.
- No ads, analytics, tracking, telemetry, or crash-reporting SDK operated by the developer.
- No developer-operated journal server or service that receives, stores, or synchronizes journal content; no remote inference endpoint or app-managed cloud sync/backup.
- The app does not automatically transmit or collect journal records or retained photos for the developer, and the developer has no app-managed remote journal access.
- The app does not use journal data to train a model.
- A PDF leaves the app only when the user invokes the system share flow and chooses a destination. That destination's policy then applies.
- The app requests exclusion of live journal files from automatic device backup. There is no iCloud journal database or app-managed sync; iOS controls backup behavior.
- V1 provides no journal-transfer feature. Same-install unfinished-draft reopening and fail-closed journal retry remain local safeguards.
- A PDF the user shares or copies is external to the app. It remains governed by the chosen destination and cannot recreate journal data or create journal entries.

**[LEGAL/APP REVIEW — BLOCKING]** Review and approve every user-directed destination exposed by the final binary, including PDF destinations and external support, privacy, runtime-source, and license links. **[OPERATOR — BLOCKING]** Reconfirm these statements against the exact Apple-processed build, its privacy manifests, linked SDKs, and an instrumented network run.

## Reviewer data and cleanup

Please use synthetic or otherwise non-sensitive test content. Individual entries can be deleted in Journal. Settings → **Erase All Journal Data…** uses two confirmations to remove every journal entry, dated no-bowel-movement/day record, stored journal photo, unfinished draft, and temporary PDF export while retaining the installed app. GI Journal stores its live journal locally and requests exclusion from automatic device backup; iOS controls backup behavior. V1 provides no journal-transfer feature; same-install unfinished-draft reopening and fail-closed journal retry remain local safeguards. Deleting or reinstalling GI Journal, erasing, losing, or resetting the iPhone, or a storage failure may permanently lose entries and photos. Temporary PDF files are deleted after the preview/share lifecycle when safe and stale temporary exports are purged on launch. A user-shared PDF remains at the chosen destination but cannot restore the journal or create journal entries.

The app does not provide a global developer-side account deletion request because there is no developer account or journal-server copy. The person can delete individual entries or use the two-confirmation local erase-all control.

## Medical limits

GI Journal is intended for personal documentation and preparation for a conversation with a qualified professional. It is not intended to detect, diagnose, prevent, monitor, predict, prognose, treat, or alleviate a disease. The user enters and reviews each saved entry, and the app does not mark entries as clinically severe.

**[LEGAL/OPERATOR — BLOCKING]** Confirm App Store medical-app disclosures, age rating, regional availability, intended-use wording, and classification before submission.

## Build identification

- Version: **[FINAL MARKETING VERSION]**
- Build: **[FINAL BUILD NUMBER]**
- Source commit: **[FINAL GIT COMMIT]**
- AppStore archive validation receipt: **[INTERNAL RELEASE RECORD REFERENCE]**
- Qualified review devices: **[FINAL DEVICE LIST]**

No diagnostic launch arguments or hidden reviewer steps are required in the public binary. **[OPERATOR — BLOCKING]** Do not submit until every statement above, including the user-directed destination disclosures, has been verified against the exact Apple-processed build and all placeholders have been replaced.

Internal Build 4/5 qualification evidence is intentionally excluded from reviewer-facing copy. It remains in `CANDIDATE_READINESS_2026-08-02.md`, `VALIDATION_REPORT_2026-08-02.md`, `PHYSICAL_INSTALL_REPORT_2026-08-02.md`, and `DEVICE_SUPPORT_MATRIX.md`. Do not paste internal paths, diagnostic run IDs, development-signing failures, or non-candidate evidence into App Review notes.
