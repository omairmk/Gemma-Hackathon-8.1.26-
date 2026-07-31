# GI Timeline for iPhone — Architecture (FINAL, frozen; round-10 errata applied; deliverables 1–13)

Prepared July 30, 2026. Round-9 and round-10 errata applied; files frozen. No further review cycles — `MOBILE_PRECHECK.md` decides. Deliverable 14 is `GI_Timeline_Build_Prompt_FINAL.md` (distinct file; self-identifying first comment).

## 1. Feasibility verdict: CONDITIONAL GO — two gates, one file

Saturday's phone build is authorized only when `MOBILE_PRECHECK.md` begins:

```
STARTER_CODE_ALLOWED: YES
STATUS: GO
```

`STARTER_CODE_ALLOWED` records the organizers' answer to (ask verbatim in Discord): **"Are teams allowed to arrive with a custom Swift starter app that already performs local image inference and includes basic persistence and test scaffolding, or may we only preinstall tools, dependencies, and model files?"** NO or unanswered → phone build off; Saturday is the Mac project. `STATUS` records the physical preflight. Contract state: no gaps known after nine review rounds.

Base (verified): Gallery iOS exists, source unpublished ([[#420](https://github.com/google-ai-edge/gallery/issues/420)](https://github.com/google-ai-edge/gallery/issues/420)); base = official **LiteRT-LM Swift package** + official sample [`[samples/ios_and_mac](https://github.com/google-ai-edge/LiteRT-LM/tree/main/samples/ios_and_mac)`](https://github.com/google-ai-edge/LiteRT-LM/tree/main/samples/ios_and_mac) (v0.14.0: README + `ContentView.swift`; preflight creates the app target, adds the vision call). Swift support is Early Preview; preflight converts it to evidence.

| Claim | Status | Source |
|---|---|---|
| Gallery iOS exists; source unpublished | CONFIRMED | [[repo](https://github.com/google-ai-edge/gallery)](https://github.com/google-ai-edge/gallery) · [[#420](https://github.com/google-ai-edge/gallery/issues/420)](https://github.com/google-ai-edge/gallery/issues/420) |
| LiteRT-LM Swift on iOS (Early Preview); image input REQUIRES `visionBackend`; `maxNumTokens` = KV-cache | CONFIRMED | [[Swift guide](https://developers.google.com/edge/litert-lm/swift)](https://developers.google.com/edge/litert-lm/swift) |
| E4B 3.65 GB; iPhone 17 Pro GPU 25 tk/s decode, 0.9 s TTFT, 3380 MB peak (text) | CONFIRMED | [[benchmarks](https://developers.google.com/edge/litert-lm/models/gemma-4)](https://developers.google.com/edge/litert-lm/models/gemma-4) |
| Sample = README + ContentView.swift at v0.14.0 | CONFIRMED | [[README](https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/v0.14.0/samples/ios_and_mac/README.md)](https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/v0.14.0/samples/ios_and_mac/README.md) |
| Official multimodal E4B artifact (`-web` = text-only, never use) | CONFIRMED | [[litert-community E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) |
| SwiftData: explicit `save()` + implicit autosave (we disable autosave) | CONFIRMED | [[ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)](https://developer.apple.com/documentation/swiftdata/modelcontext) |
| Backup exclusion = guidance; container backed up by default | CONFIRMED | [[Apple](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup) |
| Personal-team 7-day expiry: profiles, App IDs, device registrations | CONFIRMED | [[Apple](https://developer.apple.com/help/account/basics/about-your-developer-account)](https://developer.apple.com/help/account/basics/about-your-developer-account) |

## 2. Base repository

Clone [[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)](https://github.com/google-ai-edge/LiteRT-LM) at the stable tag (v0.14.0 per [[releases](https://github.com/google-ai-edge/LiteRT-LM/releases)](https://github.com/google-ai-edge/LiteRT-LM/releases)); create the "GITimeline" target; adapt the sample; pin the SPM dependency exactly (version + commit recorded; `Package.resolved` committed). Community wrappers barred. Gallery App Store app = preflight viability evidence only.

## 3. Runtime configuration

`EngineConfig(modelPath:, backend: .gpu, visionBackend: .cpu(), maxNumTokens: 2048, cacheDir:)`; one `Engine` in an actor; fresh `Conversation` per analysis; greedy decoding (`topK: 1`, minimal temperature; else record closest, call repeats a consistency check). Record the exact passing configuration.

## 4. Model decision — E4B only

`litert-community/gemma-4-E4B-it-litert-lm`. Phone gates: loads without OOM; image+text inference; Airplane-Mode cold relaunch; contract-valid output; warm ≤ ~25 s; five consecutive clean analyses; content-dependent vision gates. Any failure → `STATUS: NO-GO` → Mac build.

## 5. Preflight (pre-event, ~2 h; commits MOBILE_PRECHECK.md)

1. Record device identifier, iOS/Xcode versions, signing identity. Personal-team 7-day expiry (profiles, App IDs, device registrations): re-deploy Thursday/Friday; **never uninstall or change bundle ID after staging**.
2. Install Gallery; run Ask Image with Gemma 4 on a synthetic prop; record behavior/latency.
3. Clone at the tag; create target; adapt sample; pin; commit `Package.resolved`; build to phone. **Create the test target now, with `MockInferenceService` and `FailingEntryStore` compiling** — Saturday's final 25 minutes can be "run and fix" only if the harness already builds.
4. **Model staging contract (complete):** app sets `UIFileSharingEnabled = YES`; a Finder-visible `Documents/Import/` folder receives the artifact; before import, check free space (≥ 2× artifact size); an explicit in-app import trigger **COPIES** it to `Application Support/Models/model.tmp`; the tmp copy's **SHA-256 is verified** against the hash recorded at download; on success, atomically rename tmp to the final model path, and only then delete the `Documents/Import` source; on hash failure, delete the tmp copy and RETAIN the Import original (a move-then-verify sequence is incoherent — after a move there is no source left to fall back to). Models directory set `isExcludedFromBackup`.
5. Engine bring-up with `visionBackend: .cpu()`; iterate if vision fails; record what passes.
6. Content gates: brown vs. green synthetic clay props (watermarked SYNTHETIC) — both `image_usable: true`, colors contrast, repeated brown run identical under greedy.
7. Warm latency (runs 2–5) + peak memory over five consecutive analyses; then Airplane Mode + force-quit + relaunch + one analysis.
8. SwiftData CRUD smoke on-device. Draft-lifecycle check. **DEBUG assertions/log (no diagnostics screen):** saved image EXIF/GPS key count 0; file-protection classes on Images/Drafts/store/WAL/SHM; post-delete file absence.
9. Commit `MOBILE_PRECHECK.md`: the two gate lines; REPO block (project + test target build; pinned version + commit; `Package.resolved`; prompt/config constants); PHONE block (bundle ID; model path + verified sha256; installed build); exact engine + sampler config; measurements; offline result; five-run stability; CRUD smoke; DEBUG-assertion log; Gallery cross-check; known limitations. Honest NO-GO = successful preflight.

## 6. Components

SwiftUI (NewEntry + ReviewPanel; History + Detail) → ViewModels → `InferenceService` (actor; protocol-typed; DEBUG `MockInferenceService`), `ObservationParser` (strict decode → validate; output rendered as labeled rows — no sentence assembly), `ImageStore` (sanitize; immutable UUID drafts; copy-promote; reconcile), `EntryStore` (SwiftData behind a protocol; DEBUG `FailingEntryStore`), `SafetyRules` (pure function) → SwiftData store + `Application Support/{Images, Drafts, Models}`.

## 7. Screens and interaction — final scope (no reinstatement, ever, during the build)

Both tabs: badges "Runs locally on this iPhone" / "Documentation only — not diagnosis."

**Tab 1 — New Entry.** PHPicker only; photo REQUIRED to save. Editable date-time defaulting to now. Symptoms: the four yes/no/unsure flags (red blood; black or tarry stool; dizziness or fainting; severe or worsening pain), segmented controls with NO default, nil when untouched; note ≤500. (Pain/urgency/count fields do not exist in this build. The schema keeps their nullable columns for a future version; the UI never shows them.) **Async-state rule (final):** every photo-preparation operation and every analysis attempt carries its own unique ID — two picker operations cannot complete out of order, and a retry on the same photo is a distinct attempt. Analyze and Save enable only after the draft is fully sanitized, written, and hashed. Analyze is disabled while an attempt runs. On timeout, the attempt is invalidated, but Save/Clear/replacement remain locked until engine cancellation or completion is confirmed — a timer expiring does not mean the engine has released the file. Results carrying a stale attempt ID are discarded. **The Save transaction is itself locked:** while a save runs, Analyze, Save, Clear, and replacement are all disabled (a double tap must not create duplicates). After a successful save, one shared reset function — also used by Clear — resets the current draft/path and preparation ID, the analysis attempt and validated AI snapshot, reviewed fields and provenance state, symptom flags and note, the date to the new-entry default, and Save eligibility. **Photo replacement is transactional:** prepare and hash the NEW draft first, then swap state and delete the old draft; cancellation or failure leaves the old selection intact; stale preparation files are deleted immediately. Save button: "Save Entry" (no analysis → provenance `manual`) or **"Save Reviewed Entry"** (analysis present; pressing it is the review acknowledgment; stamps `reviewedAt`; `ai_unedited`/`ai_edited` by field diff). Review panel (after analysis): **labeled, editable rows** — Bristol type (1–7/none), Apparent color, Form, Red-appearing material, Black/tarry appearance — each labeled "AI-assisted observation." No assembled sentence, no prose of any kind; when the image was unusable, a fixed label row shows the quality issue ("Image quality: too dark — assessment not possible"). Safety card — fixed, non-blocking, iff any flag == "yes" (user-reported only; model output can never trigger it; unsure/unanswered show nothing; no reassurance when absent): "Some of the symptoms you reported can require urgent medical assessment. This app cannot determine the cause or severity. Seek urgent medical care. Call emergency services for uncontrolled bleeding, fainting, chest pain, trouble breathing, or other severe symptoms."

**Tab 2 — History.** Reverse-chronological text cards (date/time, flags summary, reviewed Bristol + color) → **Detail (minimal, required — acceptance depends on it; it is never a cut target):** image; "You reported" (nil → "Not recorded"); by provenance — `manual`: "No AI analysis was saved"; else "AI-assisted observation, reviewed by you" as labeled rows, "(edited)" for `ai_edited`; model ID footnote. Swipe-to-delete with confirmation.

## 8. Data design

**`Entry`:** id UUID; capturedAt Date; imageFilename String?; imageSHA256 String?; redBlood String?; blackTarry String?; dizziness String?; severePain String?; note String? (≤500); painScore Int?; urgency String?; bm24h Int? (schema-only; no UI); provenance String (`manual`|`ai_unedited`|`ai_edited`); reviewedAt Date?; originalAIJSON String?; reviewedJSON String?; modelID String?; createdAt/updatedAt Date. nil = "not reported," never coerced, rendered "Not recorded."

**Drafts/images:** sRGB re-encode (metadata-free by construction), ≤1024 px, JPEG ~0.8; immutable file-protected `Drafts/<UUID>.jpg`; drafts survive AI failure; deleted only on Clear, replacement, or after a successful save; launch sweep.

**Persistence (copy, don't move — with context rollback):** `autosaveEnabled = false`. **Save sequence, exactly:** copy draft to `Images/<UUID>.jpg` → `insert(entry)` → `try modelContext.save()`. **On failure: `modelContext.rollback()`** (without it, the inserted object lingers in the context and a retry produces a phantom or duplicate entry) → delete the copied image best-effort → retain the original draft and the form state → show the error. **On success:** delete the original draft, then run the shared form reset. Tests must prove zero entries exist after an injected save failure and exactly one after the retry. **Delete:** remove object → `try save()` → on throw: `rollback()`, keep the image, keep the entry visible, show a failure message; after success, delete the image file — **file removal is verified by a DEBUG assertion/log, not by asking the operator to see an invisible file.** **Launch reconciliation:** orphan images deleted; missing-file entries marked "image unavailable."

**Protection/backup:** `.completeFileProtection` on Images, Drafts, store + `-wal`/`-shm` (asserted in DEBUG in the final build). Models excluded from backup; journal data rides normal device backup. Privacy line verbatim: "The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings." No networking code paths; no analytics.

## 9. Model contract — all-enum; prompt and validator aligned

Fields: `image_usable` Bool; `quality_issue` none|too_dark|blurred|obstructed|too_far|not_target_image|other; `apparent_bristol_type` 1–7|null; `apparent_color` brown|light_brown|dark_brown|green|yellow|orange|red_appearing|black_appearing|pale_or_clay_appearing|mixed|unable_to_assess; `form` hard_lumps|lumpy_formed|cracked_formed|smooth_formed|soft_blobs|mushy|watery|mixed|unable_to_assess; `red_appearing_material`, `black_tarry_appearance` not_observed|possible|apparent|unable_to_assess. The prompt states the full consistency rule verbatim (usable ⇒ quality_issue "none"; unusable ⇒ quality_issue ≠ "none", Bristol null, the four assessment fields "unable_to_assess") so the validator never rejects an induced abstention. Validation: unknown-key rejection; exact enums; range; cross-field both directions; ONE repair; then "AI analysis unavailable," draft intact, manual save works. **`originalAIJSON` stores only the final validated response; rejected raw attempts are never persisted.** Display is labeled rows only — the app renders values, it does not write sentences.

## 10. Privacy and medical-safety boundaries

On-device inference; Airplane Mode opens the demo; no networking code paths. Metadata-free re-encodes; deletion verified; honest backup wording (§8). Model output is enums only; there is no generated prose anywhere; user-attributed displays quote the user ("You reported: red blood — yes"). Safety card user-flag-only, never blocking, no reassurance by absence, a prototype alert rule. Organizer scope verbatim: decision-support only; synthetic or public data only; no diagnosis or treatment. Synthetic watermarked props only.

## 11. Two-hour schedule (feature freeze at minute 95; scope is fixed — nothing is reinstated during the build)

0–15 verify both gate lines + REPO/PHONE + one warm analysis. 15–40 shell + SwiftData + stores skeleton. 40–65 prompt + parser + review rows + async-state rule (attempt IDs; save lock). 65–85 save/delete lifecycle (copy-promote; rollback on BOTH paths; shared reset) + History cards + Detail. 85–95 four flags + note + safety card + swipe-delete. **Tests for each block are written and run inside that block**; 95–120 strictly RERUNS the complete suite and fixes failures; final commit. Behind at minute 50 → trim Detail styling only; Detail itself is required.

## 12. Acceptance tests

**Automated (fault injection = MockInferenceService + FailingEntryStore only):** prompt example validates; unknown-key rejected; cross-field rules both directions; repair then double-failure (draft survives; manual save; rejected raw not persisted); async-state — enablement gated on draft readiness; Analyze locked during an attempt; timeout invalidates the attempt but locks persist until confirmed completion; out-of-order photo preparation resolves by prep ID; stale attempt-ID results discarded; injected save failure → `rollback()` leaves ZERO entries, the original draft untouched, the copied image cleaned; retry then yields exactly ONE entry; successful save runs the shared reset and a second entry saves cleanly from the fresh form; a save in progress locks Analyze/Save/Clear/replacement; replacement cancellation leaves the old selection intact; delete-failure rolls back with entry visible and image intact; post-delete file absence asserted; launch reconciliation (orphan image; missing-file entry); provenance transitions + `reviewedAt`; nil flags render "Not recorded"; SafetyRules truth table; DEBUG assertions — saved image EXIF/GPS 0, protection classes present.

**Operator checkpoints, in order:** Airplane Mode on → select prop → analyze → correct one field → Save Reviewed Entry → History shows it → Detail attribution correct → force-quit → relaunch → entry present → delete → entry gone from History (file removal covered by the DEBUG assertion) → five consecutive analyses clean → manual flow shows "No AI analysis was saved."

## 13. Risks

(a) Early Preview API — exact pin + `Package.resolved`; no in-window alternative; E4B failure = NO-GO in preflight. (b) Vision path — front-loaded to preflight. (c) Context/memory — 2048, measured. (d) Container loss — never uninstall/rebundle. (e) Venue thermal/latency — margin in the 25 s gate; charged phone, no case. Scope is final: never cut physical-device execution, local Gemma inference, photo selection, nil-preserving flags, review-before-save with earned acknowledgment, persistence with both rollback paths, History + minimal Detail, deletion, Airplane Mode demo, documentation-only language, the acceptance block. Never add anything.

## 14. Coding-agent prompt

`GI_Timeline_Build_Prompt_FINAL.md` — distinct, self-contained, double-gated. Frozen.

**Sources:** [[LiteRT-LM Swift guide](https://developers.google.com/edge/litert-lm/swift)](https://developers.google.com/edge/litert-lm/swift) · [[Gemma 4 benchmarks](https://developers.google.com/edge/litert-lm/models/gemma-4)](https://developers.google.com/edge/litert-lm/models/gemma-4) · [[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)](https://github.com/google-ai-edge/LiteRT-LM)/[[releases](https://github.com/google-ai-edge/LiteRT-LM/releases)](https://github.com/google-ai-edge/LiteRT-LM/releases)/[[sample](https://github.com/google-ai-edge/LiteRT-LM/tree/main/samples/ios_and_mac)](https://github.com/google-ai-edge/LiteRT-LM/tree/main/samples/ios_and_mac) · [[Gallery](https://github.com/google-ai-edge/gallery)](https://github.com/google-ai-edge/gallery)/[[#420](https://github.com/google-ai-edge/gallery/issues/420)](https://github.com/google-ai-edge/gallery/issues/420) · [[E4B artifact](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) · [[SwiftData ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)](https://developer.apple.com/documentation/swiftdata/modelcontext) · [[Apple backup guidance](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup) · [[Apple personal-team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)](https://developer.apple.com/help/account/basics/about-your-developer-account)
