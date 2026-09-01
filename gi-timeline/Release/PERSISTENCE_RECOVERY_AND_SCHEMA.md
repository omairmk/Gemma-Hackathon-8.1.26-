# Persistence integrity, retry, and schema policy

> **Current V1 predecessor-bootstrap boundary — 2026-08-05:** The immutable predecessor fixture passes both direct current-schema open/cold reopen and the full protected-data/pending-erase/real-reconciliation/ready/cold-reopen app bootstrap. The complete exact-current AppStoreTesting suite passes **121/121**. The intentionally absent fixture photo is marked unavailable while its row, filename, hash, and all other predecessor fields remain retained; immutable fixture hashes remain unchanged. A proposed automatic SQLite/WAL/SHM snapshot-and-restore layer was deliberately declined for V1 because there is no explicit migration stage and the three-file set cannot be restored atomically without new erase/privacy/photo-consistency risks. A future real schema change must use a separately reviewed side-by-side migration. This does not close signed physical in-place-update or interrupted real-migration gates. See `BUILD8_GEMMA4_CONTEXT1536_RAW_IMAGE_CORRECTION_2026-08-05.md` and the predecessor receipt it supersedes for current status.

> The filename is retained for existing historical links. In this document,
> same-install integrity and retry safeguards are not a portable recovery,
> backup, import, or restore feature. Shipping V1 provides none of those.

## Public-store bootstrap

`PersistenceBootstrap` is the only ordinary-launch path for the canonical
`GITimeline.store`. It asks SwiftData to open the existing store with the
current schema and migration plan. If that call fails, the bootstrap does not
delete, rename, replace, or create any canonical SQLite, WAL, or SHM file.

Instead, the app receives an in-memory `ModelContainer` strictly to render a
blocking journal-unavailable screen. The normal tab UI is gated on
`permitsJournalPresentation`, so an unavailable journal is never represented
as a successful empty journal. The screen tells the person to retain the app
and data rather than reset or delete it. Its `Try Again` control repeats only
the open attempt; it does not reset, replace, or write the canonical store.

## Unfinished no-photo entries

An intentional manual entry without a photo can now persist its entered form
fields in the protected draft snapshot. Its photo reference is absent rather
than synthetic, so photo hash validation remains mandatory whenever a photo
does exist. A pristine empty manual form is not persisted; if someone clears
the final entered field, any older no-photo draft snapshot is removed rather
than restoring stale content later.

## Intentional no-app-managed-backup policy

These same-install safeguards protect against an interrupted app session and an
open failure on the same installed app. It is not cloud or device backup. GI
Journal requests backup exclusion for app-created journal records, photos,
drafts, and exports; iOS controls backup behavior. GI Journal provides no
iCloud journal store, app-managed sync, or restore service. Deleting the app,
erasing or losing the device, replacing it, or device failure can permanently
remove journal data. That privacy product policy remains intentional and is
separate from the implemented local integrity and retry paths above.

Saved logs are designed to remain in the same installed container after an
ordinary app close/reopen, iPhone restart followed by unlock, or in-place app
update. Disk-backed local tests cover cold reopen and protected-data retry.
Exact processed-build physical reboot/unlock and signed in-place-update
qualification remain blocking; local tests are not that evidence.

## Schema V1 foundation

`GIJournalSchemaV1` names the existing three persisted model types without
changing their model declarations, entity names, or property names.
`GIJournalSchemaMigrationPlan` contains only V1 and no stages. A future
schema change must add a new version and a tested migration stage; V1 must not
be edited in place.

The compatibility claim is limited to the covered shape. The focused test
creates an actual unversioned SwiftData store containing only `EntryRecord`,
then reopens it through the public V1 bootstrap and compares every persisted
entry field. It also verifies the later-added timeline entities are available
without changing the legacy entry. This passed on the current simulator build.

`Fixtures/legacy-v0-synthetic-entry.json` is a deliberately synthetic,
photo-free test seed. It contains no patient record, image bytes, or real
identifiers and is packaged only with the test target.

## Release qualification still required

Before relying on a new future migration in production, retain the generated
legacy-store test, add fixtures for each released schema, and run it against
an installed upgrade on physical hardware. A bootstrap journal-unavailable screen is a
data-preserving failure mode, not a repair or data export mechanism.
