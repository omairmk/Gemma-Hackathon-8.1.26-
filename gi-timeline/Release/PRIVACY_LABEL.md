# GI Journal App Store privacy-label worksheet

Status: **draft only; not an App Store Connect submission receipt**.
Updated: 2026-09-01.

This worksheet describes the current manual-fallback public lane. Re-run it against the exact signed archive, exported IPA, installed build, current Apple definitions, public support flow, and legal review before answering App Store Connect.

## Proposed App Privacy answers

| App Store Connect question | Proposed answer | Basis |
|---|---|---|
| Does this app collect data? | **No, Data Not Collected — proposed, not submitted** | GI Journal has no developer-operated journal server, account, analytics, tracking, telemetry, crash-reporting SDK, remote inference service, or app-managed cloud sync. It does not automatically transmit journal records, photos, PDFs, prompts, or outputs to the developer. |
| Is data used to track the user? | **No** | No advertising, cross-app tracking, tracking SDK, advertising identifier, or data broker use is present in the current public lane. |
| Is data linked to the user's identity? | **No developer collection** | The app has no login, developer account identifier, or developer-received journal data. |

Apple's own App Store purchase, installation, diagnostics, and device-service processing is governed by Apple and is not a copy of the journal collected by the developer.

## Data handled locally but not collected by the developer

| Apple data category | Local use |
|---|---|
| Health | Digestive-health observations, symptoms/context, dated no-bowel-movement records, discussion bookmarks, older compatible local records, and notes entered by the person |
| Photos or Videos | User-selected or camera-captured photos retained with manual entries |
| User Content | Free-text notes and user-directed PDF content |
| Identifiers | Local record UUIDs used inside the device container only |
| Purchases | Paid app purchase handled by Apple; no app-owned entitlement server or IAP service |

The public app contains no model payload and does not analyze photos or use photos to prefill fields. Historical suggestion/provenance fields may be readable for older compatible local entries, but new manual-fallback entries do not fabricate model provenance.

## User-directed sharing

The person may create and preview a PDF for a selected date range and scope. The PDF leaves the app only when the person uses the iOS share interface and chooses a destination. The developer does not select or receive the destination or PDF. The receiving app/service's own terms and privacy practices apply after sharing. A PDF is a readable record and cannot restore the in-app journal.

## Backup and Apple-controlled services

GI Journal stores its live journal locally and requests backup exclusion for app-owned journal files, retained images, and drafts. iOS controls backup behavior. V1 provides no iCloud journal database, app-managed sync, developer-accessible backup, backup file, import, restore, or journal-transfer feature. Deleting/reinstalling the app, erasing/losing/resetting/replacing the device, or storage failure may permanently lose entries and photos.

If a selected Photos item exists only in iCloud, Apple Photos may need network access before GI Journal receives the selected item. That is Apple-controlled photo-library behavior, not developer collection by GI Journal.

## SDK and manifest inventory expected in the final archive

- Apple system frameworks for SwiftUI, SwiftData, Foundation, UIKit, PhotosUI, PDFKit, ImageIO, CoreGraphics, CoreText, CryptoKit, UniformTypeIdentifiers, Darwin, and standard Swift/runtime support as linked by the final build.
- The app privacy manifest, with no tracking, no collected-data declarations, and the reviewed accessed-API reasons.
- No ad, analytics, attribution, social-login, cloud-database, remote-config, crash-reporting, third-party AI, remote-inference, or support SDK.
- No LiteRT, Gemma, Qwen, MLX, CLiteRT, `.litertlm`, `.safetensors`, `.gguf`, or `EmbeddedModels` payload.

## Mandatory final verification

- [ ] Inspect the final `.xcarchive` and exported `.ipa`, not only source imports.
- [ ] Enumerate every embedded framework, dynamic library, resource, executable, and privacy manifest.
- [ ] Run an instrumented fresh-install, normal-flow, Airplane Mode, PDF, and relaunch network observation.
- [ ] Confirm no SDK, endpoint, telemetry, crash reporter, analytics package, remote inference, or support upload was introduced.
- [ ] Confirm permission strings describe only actual Camera and selected-photo behavior.
- [ ] Confirm PDF sharing is initiated by an explicit user action and no automatic upload exists.
- [ ] Confirm the installed build requests backup exclusion for live journal files and does not represent the request as an iOS guarantee.
- [ ] Reconcile this worksheet with the public privacy policy, support page, metadata, and App Review notes.
- [ ] Record the support provider and correspondence retention/deletion terms.
- [ ] Obtain qualified legal/App Review guidance for user-directed PDF exports and health-data classification.
- [ ] Have the App Store account holder answer the current App Privacy questionnaire and archive the submission receipt.

## Reassessment triggers

Reassess the proposed **Data Not Collected** answer before adding sync, backup, accounts, remote inference, on-device AI telemetry, support uploads, analytics, crash reporting, ads, attribution, notifications backed by a server, customer-support SDK, purchase/entitlement server, or any public AI-enabled photo suggestion route.

**[OPERATOR — BLOCKING]** Final App Privacy answers and submission receipt.
**[LEGAL — BLOCKING]** Approval that the final behavior and current Apple definitions support the proposed answers.
