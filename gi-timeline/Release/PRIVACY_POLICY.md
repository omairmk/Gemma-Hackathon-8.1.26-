# GI Journal privacy policy

> **Publication draft — updated 2026-08-13. Do not publish until every bracketed placeholder is replaced, legal review is complete, and the exact Apple-processed/TestFlight manual-fallback build passes its release, privacy, restart-after-unlock, and signed in-place-update qualification. Current source and Simulator evidence does not prove those behaviors.**

Effective date: **[EFFECTIVE DATE]**
Developer/legal entity: **[LEGAL ENTITY NAME]**
Privacy contact: **[PRIVACY EMAIL]**
Public policy URL: **[PUBLIC HTTPS PRIVACY URL]**

## Summary

GI Journal is designed to keep journal information on the user's iPhone. The app has no account, advertising, analytics, tracking, developer-operated journal server, remote model service, or app-managed cloud sync. It does not automatically transmit or collect journal information for the developer and does not use journal information to train a model. GI Journal requests exclusion of live health-journal files from automatic device backup; iOS controls backup behavior. V1 provides no journal-transfer feature. Same-install unfinished-draft reopening and fail-closed journal retry remain local safeguards.

The user controls every export. When the user chooses a destination for a PDF, that destination's privacy and retention terms apply.

## Information handled on the device

GI Journal can handle sensitive information that the user chooses to enter or attach, including:

- bowel-movement dates and reviewed stool-form observations;
- photo-usability review and retained bowel-movement photos;
- user-reviewed pain, urgency, visible red appearance, black/tar-like appearance, dizziness, severe pain, straining or incomplete evacuation, leakage or accident, and notes;
- dated no-bowel-movement records;
- older compatible timeline records retained from a prior build, if any;
- discussion bookmarks;
- historical model suggestion, review, and local provenance fields retained in entries created by an earlier compatible build, if any; and
- PDFs the user asks the app to create.

This information is processed locally to provide manual journal, editing, photo-attachment, and PDF features. The public manual-fallback app contains no model payload and does not run photo inference. Journal content is not automatically transmitted to the developer, and the developer operates no journal server for GI Journal.

## Collection by the developer

GI Journal does not collect personal data, health data, photos, diagnostics, usage data, identifiers, contacts, location, purchases, or model prompts or outputs for the developer. It contains no developer-operated analytics, advertising, tracking, telemetry, remote inference, or crash-reporting service.

Apple may process App Store purchase, installation, diagnostics, and device-service information under Apple's own terms and the user's settings. That processing is not controlled by GI Journal and is not a copy of the journal collected by the developer.

If the user voluntarily contacts **[SUPPORT EMAIL]**, the user chooses what to include and the support email provider will process that communication. Users should not send journal photos, shared PDFs, or other sensitive health information in a support request. **[OPERATOR/LEGAL — REQUIRED]** Add the support provider and its retention terms here if support correspondence will be retained.

## Camera and photo library

Camera access is used only when the user chooses to attach a photo to a manual entry. For an existing image, GI Journal presents Apple's system Photos picker and receives only the item the user selects; it does not request broad library access. The app prepares its own bounded image copy for local storage and does not analyze it, use it to prefill fields, or upload it to the developer. If the selected asset exists only in iCloud, Apple Photos may need a connection to provide it before GI Journal can attach its local copy.

The user can decline Camera access, cancel photo selection, or continue with a no-photo entry. Camera permission controls are available in iOS Settings.

## Storage, protection, and backup

Journal records and retained photo copies are stored in the app's local container. The app attempts to apply iOS complete file protection to its store and image directories. No security mechanism is absolute; device security, OS state, passcode settings, and physical access also affect protection.

GI Journal requests backup exclusion for the live journal in Application Support, including its SwiftData store and sidecars, retained images, and drafts. iOS controls enforcement of platform file attributes. The public app contains no model payload. GI Journal does not provide an iCloud journal database, cloud account, app-managed synchronization, or V1 journal-transfer feature.

GI Journal does not intentionally delete saved logs during an ordinary app close and reopen, an iPhone restart followed by unlock, or an in-place app update. iOS and storage integrity still govern retention. Deleting or reinstalling GI Journal, erasing, losing, resetting, or replacing the device, or a storage failure may permanently lose entries and photos. The developer cannot remotely access or recreate the in-app journal. A PDF is readable but cannot recreate the journal or create journal entries.

## User-directed export and disclosure

GI Journal can create a PDF for a user-selected inclusive date range and All or Marked scope. The PDF can contain sensitive journal fields and dated no-bowel-movement records, and includes every attached photo for its selected entries. If any expected attached photo cannot be verified, no PDF is created. The app previews the PDF locally. It is disclosed only when the user chooses a destination through the iOS share interface.

The recipient, Files location, cloud provider, messaging app, email provider, clinician system, printer, or other selected destination applies its own security, retention, and privacy practices. Users should verify the destination before sharing. **[LEGAL/APP REVIEW — BLOCKING]** Review the exact final PDF-sharing destinations and disclosure against current requirements before release.

## Retention and deletion

- Saved entries and their retained photo copies remain on the device until the user deletes the entry or removes the app.
- A saved entry can be edited. Its identity, original creation timestamp, and retained photo bytes/hash remain attached while editable journal fields are updated. Historical entries that already contain immutable suggestion provenance keep it; new manual-fallback entries do not fabricate model provenance.
- Deleting an entry removes its local database record and its retained image copy through a coordinated local transaction. If cleanup cannot be verified, GI Journal reports the problem instead of claiming that deletion completed.
- Dated no-bowel-movement records remain until the user replaces/removes the record, saves a bowel-movement entry on that date, or invokes **Erase All Journal Data**. Older compatible timeline records from earlier builds are not shown as treatment controls in the simplified public UI but remain stored locally and covered by erase so an upgrade does not silently discard them.
- **Erase All Journal Data** uses two confirmations and permanently removes every journal entry, dated day record, older compatible timeline record, stored journal photo, unfinished draft, and temporary PDF export. It leaves the installed app in place. If an interruption prevents the erase from being verified, the app blocks ordinary journal use and offers **Try Again** until the pending erase is safely resolved.
- Temporary PDF exports are removed after the preview/share lifecycle when safe; interrupted/stale temporary exports are purged on a later launch.
- Removing the app normally removes its local app container. GI Journal provides no V1 journal-transfer feature. A separately shared/copied PDF remains outside the app under the destination's retention policy but cannot restore the journal or create journal entries.
- The developer cannot remotely access or delete an in-app journal because the developer has no account or journal-server copy.

## Model use

The public app bundle contains no model payload, and `MANUAL_FALLBACK_RELEASE` does not select, initialize, or invoke a model. The public interface treats photos only as manual-entry attachments and does not analyze or prefill them. Internal candidate code and historical suggestion provenance are not public features. Neither the developer nor the app uses journal content, photos, historical suggestions, or corrections to train or fine-tune a model.

## Medical limits

GI Journal is a documentation tool for people working with an established care team, not a diagnostic or treatment service. It does not determine whether a person has a condition, assess its cause or severity, or recommend treatment. **[LEGAL/REGULATORY — BLOCKING]** Approve the intended-use language and medical-device classification before publication.

## Children

GI Journal is not directed to children **[LEGAL/OPERATOR — CONFIRM AGE THRESHOLD AND TERRITORIES]**. Because the app has no account or developer data collection, the developer does not knowingly collect children's personal information through the app. A parent or guardian remains responsible for device access and any information entered or shared.

## Changes to this policy

Material changes will be posted at **[PUBLIC HTTPS PRIVACY URL]** with a new effective date. A product update will be used when a change affects in-app data handling. Historical policy versions should remain available at **[POLICY ARCHIVE URL OR PROCESS]**.

## Contact

Privacy questions: **[PRIVACY EMAIL]**
Support: **[SUPPORT EMAIL]**
Legal entity and mailing address, if required: **[LEGAL ENTITY AND POSTAL ADDRESS]**

No placeholder may remain in the published policy or submitted App Store metadata.
