# GI Journal App Store privacy-label worksheet

> **Draft assessment — updated 2026-08-03:** Based on the intended local-only public build with user-directed PDF export and no V1 journal-transfer feature. Same-install unfinished-draft reopening and fail-closed journal retry remain local safeguards. This is not an App Store Connect submission receipt. Re-run the assessment against the exact uploaded archive and current Apple definitions.

## Proposed App Privacy answers

| App Store Connect question | Proposed answer | Basis |
|---|---|---|
| Does this app collect data? | **No, Data Not Collected — proposed, not submitted** | The app does not automatically transmit journal records, photos, symptoms, no-bowel-movement records, PDFs, or model inputs/outputs to the developer; it has no developer-operated journal server. Final archive/runtime/network/support review remains required. |
| Is data used to track the user? | **No** | No advertising, cross-app tracking, tracking SDK, advertising identifier, or data broker use |
| Is data linked to the user's identity? | **No developer collection** | No account, login, user identifier, or developer-received journal data |

On-device handling is not marked as developer collection when the app does not transmit it off the device for developer or third-party collection, subject to Apple's then-current definitions. User-directed sharing and Apple-controlled services are described separately below.

## Data types handled locally but not collected by the developer

| Apple data category | Local use |
|---|---|
| Health | Reviewed digestive-health observations, user-reported symptoms, dated no-bowel-movement records, older compatible local records, and notes |
| Photos or Videos | User-selected or camera-captured photo retained with an entry and processed locally |
| User Content | Free-text journal notes and user-directed PDF content |
| Diagnostics / Usage Data | Not gathered by an app-owned analytics or crash service |
| Identifiers | Local UUIDs identify records inside the device container only; they are not transmitted |
| Purchases | Apple handles the paid download; the app has no IAP receipt service or account entitlement server |

## User-directed sharing

The user can ask the app to create a PDF and then choose a destination through an iOS system interface. The developer does not select or receive the destination or PDF. Under the intended design this is a user-directed disclosure, not developer collection. Once exported, the receiving app/service's privacy terms apply. The PDF is not an app backup and cannot recreate journal data or create journal entries.

## Backup and Apple-controlled services

GI Journal requests backup exclusion for the live journal in Application Support, including its SwiftData store and sidecars, retained images, and drafts. iOS controls backup behavior. The public app contains no model payload. It provides no account, CloudKit journal database, automatic cloud sync, developer-managed backup, or V1 journal-transfer feature. Same-install unfinished-draft reopening and fail-closed journal retry remain local safeguards. App deletion/reinstall, device erasure, loss/reset/failure, or replacement may permanently lose entries and photos. A PDF cannot restore the journal.

Apple separately processes App Store purchase and installation information under Apple's terms. That does not give the developer a copy of the journal.

## SDK and manifest inventory expected in the final archive

- Apple system frameworks used for UI, SwiftData, photos/camera, PDF, cryptography, and file handling.
- LiteRT-LM Swift package and its `CLiteRTLM` binary framework.
- No ad, analytics, attribution, social-login, cloud-database, remote-config, or crash-reporting SDK.
- App privacy manifest and required third-party SDK privacy manifest present and valid.

## Mandatory final verification

- [ ] Inspect the final `.xcarchive` and exported `.ipa`, not only source imports.
- [ ] Enumerate every embedded framework, dynamic library, resource bundle, and privacy manifest.
- [ ] Run an instrumented fresh-install/normal-flow/Airplane Mode network observation and record the result.
- [ ] Confirm no new SDK, endpoint, telemetry, crash reporter, analytics package, or support upload was introduced.
- [ ] Confirm permission strings describe only actual Camera and Photo Library uses.
- [ ] Confirm PDF sharing is initiated by an explicit user action and no automatic upload exists.
- [ ] Confirm the final installed build requests backup exclusion for the live journal: Application Support store and sidecars, retained images, and drafts. Record the inspected resource values without representing the request as an iOS guarantee; separately verify the recreatable runtime-cache location/protection.
- [ ] Obtain Account Holder/qualified privacy and compliance approval for retaining that exclusion for non-purgeable, difficult-to-recreate live journal data. Apple's current [`isExcludedFromBackupKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey) reference frames exclusion for cache and other App Support files that are not necessary in a backup, while the related [`isExcludedFromBackup`](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup) guidance warns against relying on it for user documents; Apple's current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) separately impose special restrictions on health information and iCloud. These sources do not decide GI Journal's app-specific posture. Re-apply and verify the resource value after relevant file operations. This policy question remains unresolved.
- [ ] Confirm public UI and support wording accurately distinguish same-install persistence and draft/store retry safeguards, requested automatic-backup exclusion, permanent-loss risks, and non-restorable PDFs.
- [ ] Reconcile this worksheet with the public privacy policy and App Review notes.
- [ ] Record the support provider and correspondence retention/deletion terms; confirm that voluntary support contact does not create an undisclosed app collection path.
- [ ] Obtain qualified legal/App Review guidance for user-directed PDF exports to external destinations; do not infer an exception to Apple's health-data rules.
- [ ] Have the App Store account holder answer the current App Privacy questionnaire and archive the submission receipt.

## Reassessment triggers

The proposed **Data Not Collected** answer must be reassessed before adding any of the following: sync, backup, accounts, remote inference, support uploads, analytics, crash reporting, ads, attribution, notifications backed by a server, customer-support SDK, or purchase/entitlement server.

**[OPERATOR — BLOCKING]** Final App Privacy answers and submission receipt.
**[LEGAL — BLOCKING]** Approval that the final behavior and current Apple definitions support the proposed answers.
