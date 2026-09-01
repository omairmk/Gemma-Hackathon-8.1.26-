# GI Journal App Store metadata

> **Current release direction — 2026-08-30:** Public `MANUAL_FALLBACK_RELEASE` copy describes photos only as manual-entry attachments; it does not advertise photo analysis, model suggestions, or prefill. The public App Store configuration contains no model payload. **NOT PUBLISHABLE** until exact-build qualification and the open operator/legal fields are complete.

> **Draft — updated 2026-08-03:** Copy is scoped to the simplified public-release build. Replace every bracketed placeholder, verify character limits in App Store Connect, and reconcile this document with the final processed binary before submission.

## Commercial model

- Distribution: paid download.
- Access: all features are available after the App Store purchase.
- In-app purchases: none.
- Subscriptions: none.
- Account or sign-in: none.
- Advertising: none.

**[OPERATOR — BLOCKING]** Select the price tier, territories, availability date, tax category, and whether Family Sharing is enabled.

## Product fields

| Field | Proposed value |
|---|---|
| Name | GI Journal |
| Subtitle | Private digestive health log |
| Primary category | Health & Fitness |
| Secondary category | Medical |
| Bundle ID | `com.omairmkhan.GITimeline` |
| SKU | **[OPERATOR — REQUIRED]** |
| Copyright | **[LEGAL ENTITY] © 2026** |
| Privacy Policy URL | **[PUBLIC HTTPS PRIVACY URL]** |
| Support URL | **[PUBLIC HTTPS SUPPORT URL]** |
| Marketing URL | **[OPTIONAL PUBLIC HTTPS MARKETING URL]** |
| Regulated medical device status | **[ACCOUNT HOLDER/LEGAL — DECLARE FOR EU/EEA, UK, AND US]** |
| EU Digital Services Act trader status | **[ACCOUNT HOLDER/LEGAL — DECLARE; VERIFY DISPLAY CONTACTS IF TRADER]** |
| Accessibility Nutrition Labels | **[PUBLISH ONLY FEATURES QUALIFIED ON THE FINAL iPHONE BUILD]** |

Category selection is provisional. **[OPERATOR/LEGAL — BLOCKING]** Confirm the category, age-rating answers, medical-app declarations, and local regulatory obligations in every offered territory.

## Promotional text

Keep a private digestive-health journal with optional photo attachments, no-bowel-movement days, bookmarks, and clinician-friendly PDF summaries.

## Description

GI Journal helps you keep a private, structured record of digestive-health observations on your iPhone.

The public release supports complete manual logging with or without an attached photo. The person enters editable photo usability, subject, Bristol/form, apparent color, and possible red/blood-like or black/tar-like appearance fields alongside symptoms and context. This public fallback stores attached photos with entries but does not analyze them or use them to prefill fields.

Use Journal to revisit and edit saved entries or bookmark them for discussion. On Log, record a dated day with no bowel movement instead of being asked to record every bowel movement.

Create a bounded, photo-inclusive PDF for an inclusive date range, including dated no-bowel-movement records, preview it on your device, and choose where to share it. Every expected attached photo must verify or no PDF is created. A PDF is a readable record and cannot restore the journal or create journal entries.

Privacy is built into the product:

- No account or sign-in.
- No ads or analytics.
- No developer-operated journal server or app-managed cloud sync.
- GI Journal does not automatically upload journal data or photos to the developer. Attached photos are stored locally with manual entries, and a PDF leaves only when you explicitly use system sharing.
- GI Journal stores its live journal locally and requests exclusion from automatic device backup; iOS controls backup behavior. It does not provide a backup file or a way to restore journal data after app deletion/reinstall, device erasure/loss/reset/replacement, or storage failure. A PDF cannot restore the journal.
- GI Journal does not intentionally delete saved logs during an ordinary app close/reopen, iPhone restart followed by unlock, or in-place app update. iOS and storage integrity still govern retention.
- The public app contains no model payload and does not train on your journal.

GI Journal is a documentation tool for people working with an established care team. It does not diagnose a condition, assess cause or severity, or recommend treatment. Every saved entry remains user-entered and editable.

One paid download includes the complete app. There are no subscriptions or in-app purchases.

### Pre-publication approval — not listing copy

**[LEGAL/REGULATORY — BLOCKING]** Approve the intended-use wording and medical-device classification before publication.

## Keywords

`digestive,stool,Bristol,symptom,journal,tracker,health,PDF,private,on-device,bowel`

Verify the final comma-separated field against App Store Connect's current character limit.

## Version 1.0 release notes

**Draft; publish only after exact-build qualification:** Initial public release of GI Journal: complete manual logging with optional photo attachments, dated no-bowel-movement records, saved-entry editing, discussion bookmarks, and clinician-friendly photo-inclusive PDF export—all without an account or subscription.

## Screenshot narrative

Use non-sensitive synthetic data only. Do not imply diagnostic accuracy.

1. **Add an optional photo** — Attach a photo to a complete manual entry; the public version does not analyze or prefill it.
2. **Save once** — Complete the displayed entry and save it with one action.
3. **Log a day without a bowel movement** — Choose today or another date from Log.
4. **Keep your journal useful** — Reopen, edit, delete, or bookmark saved entries.
5. **Prepare for a conversation** — Preview and share a date-bounded PDF you control.

**[OPERATOR — BLOCKING]** Produce screenshots from the final AppStore binary with approved synthetic fixtures. For the current 6.9-inch iPhone class, Apple accepts portrait `1260 × 2736`, `1290 × 2796`, or `1320 × 2868` pixels (and the corresponding reversed landscape dimensions). Verify the requirements again at capture time against [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/). Ensure status bars, dates, model wording, and visible features match the submitted build.

## App preview and localization

- App preview video: optional; none is required for 1.0.
- Initial language: English **[OPERATOR — CONFIRM]**.
- Localization: do not claim localized availability until app strings, metadata, screenshots, privacy policy, and support content are localized together.

## URLs and contact placeholders

- Legal developer/entity: **[LEGAL ENTITY NAME]**
- Privacy contact: **[PRIVACY EMAIL]**
- Support contact: **[SUPPORT EMAIL]**
- Support URL: **[PUBLIC HTTPS SUPPORT URL]**
- Privacy URL: **[PUBLIC HTTPS PRIVACY URL]**
- Review contact name/phone/email: **[APP REVIEW CONTACT]**

No placeholder may appear in submitted metadata or the public policy.

## Current App Store Connect declarations — verified 2026-08-03

- A privacy policy URL and accurate app-level data-handling answers are required. Reconcile third-party runtime behavior before selecting “Data Not Collected”; see [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
- Because the proposed primary/secondary categories include Health & Fitness or Medical, the Account Holder or Admin must complete Apple's region-specific regulated-medical-device declaration. This document does not decide the legal status; see [Declare regulated medical device status](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status).
- Declare EU Digital Services Act trader status even if EU distribution is disabled. A paid app is one factor Apple lists for the legal self-assessment; if declared a trader, verify the public address/phone/email requirements. See [Apple's DSA trader workflow](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements).
- Complete iPhone Accessibility Nutrition Labels only after the exact processed build passes the corresponding criteria. Draft answers are not evidence; see [Manage Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/).
