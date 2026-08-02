# Repository hygiene and public-readiness record

Revalidated against the Kaggle phone-source publication candidate on 2026-08-01.

- [x] Intended publication diff and commit range reviewed.
- [x] `.gitignore` excludes credentials, signing profiles, user data, model weights, DerivedData, result bundles, local databases, and private logs.
- [x] Tracked-file scan found no credentials, tokens, private keys, provisioning profiles, Apple Team ID, device identifiers, real health records, or model weights.
- [x] Owner-machine absolute paths and hardware details were removed from the current tree.
- [x] All retained screenshots and fixtures are synthetic, sanitized, and free of identifying metadata.
- [x] The six stale pre-native screenshots were removed; `native-*` captures match the current review-first flow.
- [x] `git diff --check` passes.
- [x] The host SwiftPM suite passes 14/14 tests in the publication worktree.
- [x] The arm64 iOS Simulator app suite passes 41/41 tests with pinned LiteRT-LM revision `f73637c57f0940b53da184e0d5adfc52a4e55eef`.
- [x] The clean Hackathon arm64 Simulator build succeeds with the exact pinned model embedded.
- [x] Current documentation distinguishes real-Gemma Simulator evidence from deterministic UI mocks and from unproved physical-iPhone/offline claims.
- [x] The team-package archive passes integrity testing, strict ad-hoc code-signature verification, exact model SHA-256 verification, and split/reassembly checksum verification.
- [x] Project-authored source is licensed under Apache-2.0; `NOTICE` identifies LiteRT-LM and the exact separately obtained E4B model.
- [x] Public instructions do not advise bypassing platform security, licensing, or medical care.

## Current evidence boundary

- Real Gemma 4 E4B in arm64 iPhone Simulator: **PASS**
- Brown/green/control pixel dependence: **PASS**
- Editable review/save/History/relaunch: **PASS**
- Physical-iPhone bridge: **PASS / local pixel facts → embedded Gemma text mode**
- Physical raw-image Gemma inference: **BLOCKED / not claimed**
- Offline iPhone operation: **BLOCKED / not claimed**

Re-run this checklist if the source, package, model, or evidence set changes.
