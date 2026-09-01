# Restore and verify the GI Journal V1 manual-first archive

Remote verification is currently blocked. After the archive branch and tag have been pushed, restore into a new directory:

```bash
git clone --single-branch --branch archive/2026-09-01-apple-native-v1 \
  https://github.com/omairmk/Gemma-Hackathon-8.1.26-.git gi-journal-manual-fallback-v1
cd gi-journal-manual-fallback-v1
git fetch origin tag gi-journal-manual-fallback-v1-2026-09-01-v2
git checkout --detach gi-journal-manual-fallback-v1-2026-09-01-v2
```

Verify the immutable parent-bound seal and Git object graph:

```bash
python3 gi-timeline/Scripts/VerifyFinalSourceSnapshotManifest.py \
  gi-journal-manual-fallback-v1-2026-09-01-v2
git fsck --full
```

Run source-level checks:

```bash
swift test --package-path gi-timeline
gi-timeline/Scripts/ValidateLocalOnlySource.sh
gi-timeline/Scripts/TestAppStoreModelGateNegative.sh
```

After an Xcode build resolves packages, run `gi-timeline/Scripts/ValidateResolvedSourcePackages.sh` against the exact generated `SourcePackages` directory.

For a local-only verification before GitHub authentication is restored, clone the local repository into a new temporary directory, check out the same tag, and run the identical seal, fsck, and source checks. A successful local clone does not substitute for `git ls-remote` plus a fresh clone from GitHub.

The production `AppStore` configuration additionally requires:

- the exact clean content commit and tree values;
- owner-approved public HTTPS privacy and support URLs;
- signing identity/profile and Apple account authority for a signed archive or TestFlight export.

Do not infer Apple-native AI, physical-device, TestFlight, or App Store readiness from a successful source restore. This tag preserves the manual-first lane.
