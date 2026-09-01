# Restore and verify the pre-change snapshot

Clone only the archive branch into a new directory:

```bash
git clone --single-branch --branch archive/2026-09-01-pre-apple-native \
  https://github.com/omairmk/Gemma-Hackathon-8.1.26-.git gi-journal-pre-apple-native
cd gi-journal-pre-apple-native
```

Verify the immutable tag and repository object graph:

```bash
git rev-parse HEAD
git rev-parse gi-journal-pre-apple-native-2026-09-01^{}
git fsck --full
```

Verify the source manifest and run the source-level tests:

```bash
python3 gi-timeline/Scripts/VerifySourceSnapshotManifest.py \
  gi-timeline/coordination/gi-journal-v1-2026-09-01/SOURCE_SNAPSHOT_MANIFEST.json
swift test --package-path gi-timeline
cd gi-journal
python3 -m venv .venv-smoke
. .venv-smoke/bin/activate
python -m pip install pytest==9.1.1 pydantic==2.13.4
python -m pytest -q tests/test_schemas.py
```

The complete historical `gi-journal` Python suite also binds tests to a local
virtual-environment executable and an excluded Gemma snapshot. In the sanitized
snapshot it is expected to report 26 passes and seven resource-dependent
failures until those reproducible but intentionally unpublished dependencies
are restored from `gi-journal/model_manifest.json`. Those dependencies are not
required by the manual-first iOS source snapshot.

The pre-change snapshot intentionally retains the historical manual-first shipping configuration. Do not interpret a successful restore or test as Apple-native AI, device, signing, TestFlight, App Store, or clinical evidence.
