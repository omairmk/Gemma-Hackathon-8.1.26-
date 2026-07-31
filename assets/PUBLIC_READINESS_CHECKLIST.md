# Repository hygiene and public-readiness checklist

Use before sharing a repository, demo video, or Kaggle link. Check each item against the actual selected build.

- [ ] `git status --short` reviewed; only intended files are included.
- [ ] `git log -1 --oneline` recorded for the submission revision/tag.
- [ ] `.gitignore` excludes `.env`, credentials, tokens, private keys, signing profiles, `.xcuserdata`, `DerivedData`, model artifacts unless redistribution is explicitly permitted, local databases, journal images, drafts, logs, and build outputs.
- [ ] `git ls-files | rg -i '(\.env|credential|secret|token|apikey|\.p12|\.mobileprovision|\.sqlite|draft|journal|\.jpg|\.jpeg|\.png)'` reviewed; every match is intentional and safe to publish.
- [ ] `git diff --check` has no whitespace errors.
- [ ] README gives reproducible setup, supported hardware/runtime, exact model acquisition instructions, and a clear “not medical advice/diagnosis” boundary.
- [ ] README separates verified results from planned/unverified device claims.
- [ ] No screenshots, fixtures, logs, or demo media contain real patient data, account identifiers, location metadata, or secrets.
- [ ] Synthetic images visibly say `SYNTHETIC`; provenance/license/source is documented.
- [ ] Model and runtime licenses, redistribution limits, and required attributions are checked before committing weights/artifacts.
- [ ] Dependency licenses/notices and event rules are reviewed; required Gemma/Kaggle/event attribution is included verbatim where required.
- [ ] Public instructions do not tell users to bypass platform security, licensing, or medical care.
- [ ] A clean clone/setup has been attempted **[or mark not run]**; tests/build commands and their actual result are recorded.
- [ ] No physical-device, latency, offline, privacy, or accuracy assertion appears unless backed by saved evidence.

**Final stop condition:** If any secret, real health image, uncertain license, or unverified claim remains, do not publish. Remove/replace it and rerun the relevant check.
