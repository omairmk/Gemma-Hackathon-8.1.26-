# GI Journal persistence and migration architecture

> **Implementation supersession — 2026-08-02; scope clarification — 2026-08-03:** This document preserves the original architecture and acceptance design. The public launch path now uses `GIJournalSchemaV1`, `GIJournalSchemaMigrationPlan`, and `PersistenceBootstrap`; a failed canonical-store open presents a blocking, retry-only local safeguard rather than a replacement empty journal. The current transaction layer also gates ordinary writes during pending erase, invalidates stale in-flight writers with a process-local epoch, and reconciles interrupted file cleanup. See `PERSISTENCE_RECOVERY_AND_SCHEMA.md` and the candidate validation ledger for the implemented scope and test evidence. Any historical journal export, import, or cross-device restoration proposal in this document is deferred to post-V1 and is neither a shipping feature nor a V1 release blocker. The remaining V1 migration work is release qualification: broaden immutable LegacyV0 fixtures beyond the covered entry shape, exercise installed physical upgrades and interruption cases, decide timezone semantics before a later schema, and preserve this V1 definition unchanged.

> **Architecture authority — 2026-08-02:** Preserve every existing journal record and patient-facing feature. The current unversioned SwiftData layout must be treated as historical data, not silently reinterpreted or replaced. This design is required before a public schema change.

## Objectives

These are release acceptance objectives. They are not claims that a physical
signed update has already preserved a production journal.

1. Existing journals must open in place after an app update.
2. Entry fields, photos, review provenance, bookmarks, completeness answers, and treatment changes retain their meaning.
3. A failed migration never presents a new empty journal as success.
4. Migration remains local, privacy-protected, deterministic, and testable from immutable fixtures.
5. Schema work cannot remove the manual path, photo review, Journal, Progress, delete, or export capabilities.

## Current persistence baseline

The application currently creates one SwiftData container with:

- `EntryRecord`
- `DailyCompletionRecord`
- `TreatmentEventRecord`

The store lives under Application Support as `GITimeline.store` with SQLite sidecars. Retained entry images are separate protected files referenced by filename and SHA-256. The current app uses an unversioned `Schema` and aborts launch if container construction fails.

The first migration task is to capture an immutable, privacy-safe store fixture created by the last unversioned build. Call this import baseline **LegacyV0**. It is evidence input, not a schema users can recreate after the model definitions change.

## LegacyV0 field inventory

### Entry

Identity/time: `id`, `capturedAt`, `createdAt`, `updatedAt`.
Photo: `imageFilename`, `imageSHA256`, `imageUnavailable`.
Human context: `redBlood`, `blackTarry`, `dizziness`, `severePain`, `note`, `painScore`, `urgency`, `bm24h`, `confirmedBristolType`, `confirmedPhotoUsable`, `mixedForm`, `strainingOrIncomplete`, `leakageOrAccident`.
Review/provenance: `analysisSource`, `analysisPipelineVersion`, `provenance`, `reviewedAt`, `originalAIJSON`, `reviewedJSON`, `modelID`, `modelProvenanceJSON`.
Journal state: `markedForDiscussionAt`.
Engineering-only legacy marker: `demoKind`.

### Daily completeness

`dayKey`, `dayStart`, `answerRawValue`, `createdAt`, `updatedAt`.

### Treatment event

`id`, `effectiveDate`, `kindRawValue`, `name`, `doseOrNote`, `createdAt`, `updatedAt`.

Nil optional values are meaningful legacy state and must not be replaced with invented clinical answers. `bm24h`, `painScore`, and any schema-only field must be preserved even when the current UI does not expose it.

## Versioning design

### SchemaV1: preservation baseline

Define a `VersionedSchema` whose models are storage-compatible with LegacyV0. Use explicit schema identifiers and retain persisted property names/types. The V1 migration must be lightweight and must not rewrite clinical content merely to normalize it.

V1 also becomes the reference for fresh installs. If SwiftData cannot attach LegacyV0 directly to V1, use a bounded, tested custom stage that copies every field to a new versioned store while the original remains untouched until validation succeeds.

### Future versions

Every later version must declare:

- source and destination schemas;
- lightweight versus custom stage;
- field-by-field semantic mapping;
- default rules that never create a patient answer;
- image/file operation ordering;
- validation counts and hashes;
- rollback/recovery behavior; and
- fixture/test coverage.

Use additive optional properties when possible. Renames require explicit original-name mapping or a custom copy. Type changes, relationship changes, uniqueness changes, entity splits/merges, or timezone normalization require a custom migration and independent validation.

## Proposed schema roadmap

| Version | Purpose | Migration rule |
|---|---|---|
| LegacyV0 | Existing unversioned field layout | Read-only input fixture; never mutate it in tests |
| V1 | Versioned equivalent of all current records | Preserve every value and external image reference |
| V2, if approved | Explicit local-day timezone identity and support metadata | Do not regroup historical days without a documented user-visible rule |
| V3, if approved | Separate confirmed clinical record from raw suggestion/provenance artifact | Preserve original and reviewed JSON; confirmed fields remain authoritative |

This roadmap does not authorize V2 or V3. Each needs a product decision, migration fixture, and release gate.

## Transaction and file protocol

SwiftData records and image files are not one atomic database transaction, so migration uses a staged protocol:

1. Confirm protected data is available, free space is sufficient, and no migration lease is active.
2. Close ordinary writers and create a protected, local migration workspace excluded from app-managed export/share.
3. In a future migration implementation, make a same-device rollback copy of the store and sidecars for migration rollback only. Request backup exclusion for it and exclude it from app-managed sharing; iOS controls backup behavior. This is not cloud sync, a user backup, or a restore feature; delete it after committed validation and a bounded retention window.
4. Migrate database records without modifying the original retained image files.
5. Validate entity counts, unique IDs/keys, required values, enum raw values, timestamps, JSON parseability where applicable, and every image filename/SHA reference.
6. Reconcile referenced image existence. A missing file sets explicit unavailable state; it never causes deletion of the journal record.
7. Commit the destination store, reopen it through the normal container, repeat invariants, then mark the migration complete.
8. Only after successful reopen may orphan cleanup run. It must never delete a file referenced by the original or destination store.
9. Remove migration scratch/rollback material according to the approved retention rule.

Every stage must be idempotent or carry a durable state marker so termination cannot cause a double transform.

## V1 data-integrity failure behavior

This is local store-integrity handling, not a portable backup, import, or restore
feature. Any future read-only data-remediation or export tooling requires a
separately designed, tested, and approved post-V1 scope.

On container or migration failure:

- do not call `fatalError` in the public user path;
- do not delete, rename over, reset, or create a replacement empty canonical store;
- preserve the original store and images;
- show a plain blocking state offering Retry after device unlock or storage remediation and a privacy-safe support path;
- record only redacted failure class, schema versions, app build, and stage—never note text, symptoms, image names/paths, JSON, or record identifiers;
- do not expose read-only/export remediation tooling in V1; and
- require explicit user action for any destructive remediation option.

If rollback validation fails, stop and preserve both copies for local manual remediation. Do not improvise data deletion.

## Repository boundary

Views and view models should submit validated domain commands to repositories. Repository validation must enforce the same required review, Bristol/form, symptom, note-length, and photo-tuple invariants as the UI so imports, migrations, tests, and future alternate screens cannot persist invalid records.

Raw model output is evidence, not the confirmed clinical record. Preserve:

- immutable raw suggestion plus model/pipeline provenance;
- separately stored human-confirmed fields;
- whether the result was manual, AI unedited, or AI edited; and
- review timestamp.

Do not recompute past confirmed records when the model or parser changes.

## Timezone rule requiring product decision

Daily completeness currently stores a local `dayKey`/`dayStart`, treatment events store a date, and later calculations can use the device's current timezone. Travel can therefore regroup history or change a before/after window.

Before a schema change, choose and document one rule:

- preserve the timezone/calendar identity captured with each local clinical day; or
- intentionally display/group using the current timezone with explicit user-facing behavior.

The recommended durable design stores the originating IANA timezone identifier, local calendar identifier, and canonical local-day components for new records while leaving existing V1 records unchanged until a reviewed migration rule exists.

## Required fixtures

All fixtures must contain synthetic, non-health data and be committed without real photos or identifiers.

- Empty LegacyV0 store.
- One no-photo manual entry with every optional state represented across rows.
- Photo entries for AI unedited and AI edited provenance with known image SHA-256.
- Legacy rows where explicit confirmed type is nil but reviewed JSON exists.
- Marked and unmarked entries.
- Daily-completeness records around DST start/end.
- Multiple treatment kinds and boundary dates.
- Missing-image and orphan-image cases.
- Duplicate/invalid-key corruption fixture handled fail-closed.
- Interrupted migration markers for each transaction stage.
- Disk-full/protected-data-unavailable test doubles.

## Acceptance comparison

For every supported source version, automate:

1. Copy fixture to a fresh application container.
2. Record field-by-field canonical snapshots and image hashes.
3. Launch the candidate and migrate in place.
4. Reopen after process termination.
5. Compare IDs, dates, nils, raw enum values, notes, JSON, provenance, marks, daily answers, treatments, and image hashes.
6. Exercise Journal/detail, Progress, delete, bookmark, new photo/no-photo save, and PDF export.
7. Prove the original fixture remains recoverable on injected failure.

Row counts alone are insufficient.

## Historical/superseded operator-product blockers

> This table preserves the earlier architecture plan. It is not the active Build 8 V1 go/no-go ledger. In particular, its recovery-UI and temporary recovery-copy rows do not authorize or require encrypted portable recovery, export/import, or restore in shipping V1; Recovery V2 is deferred post-V1 and is not a V1 blocker. See `RELEASE_CHECKLIST.md` for active release gates.

- **[HISTORICAL ENGINEERING BLOCKER]** Freeze and check in the LegacyV0 fixture before modifying model declarations.
- **[HISTORICAL ENGINEERING BLOCKER]** Implement versioned schemas, migration plan, recovery UI, and redacted diagnostics.
- **[HISTORICAL PRODUCT BLOCKER]** Approve timezone semantics before a later schema and sign the implemented 1.0 treatment policy: ordinary Progress UI supports add, correction, and permanent marker deletion without deleting journal entries.
- **[HISTORICAL PRIVACY BLOCKER]** Approve the local temporary migration-recovery copy, protection, backup exclusion, and deletion window; reconcile with `PRIVACY_POLICY.md`.
- **[HISTORICAL QA BLOCKER]** Sign the full fixture/version matrix for the final build.

The historical conclusion is retained without change: a public release may ship with only V1, but it must have a trustworthy path for existing LegacyV0 data and a repeatable foundation for the next schema. It does not establish a shipping-V1 portable recovery or restore feature.
