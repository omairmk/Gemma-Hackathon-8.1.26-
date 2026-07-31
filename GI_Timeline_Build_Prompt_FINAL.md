# GI Timeline — Coding-Agent Build Prompt (FINAL, frozen; round-10 errata applied; two-hour window)

<!-- BUILD PROMPT, not the architecture document. If this text contains deliverables
     1–13 or a confirmed/assumed table, the wrong file was attached — stop and
     request GI_Timeline_Build_Prompt_FINAL.md. -->

You are a senior iOS engineer building on a physical iPhone (newest Pro Max) during a two-hour hackathon window, with the owner present as operator. Preflight produced: the "GITimeline" Xcode project (target built around the official LiteRT-LM `samples/ios_and_mac` sample, vision call added); a compiling TEST TARGET including `MockInferenceService` and `FailingEntryStore`; the LiteRT-LM Swift package pinned exactly with `Package.resolved` committed; Gemma 4 **E4B** staged and SHA-256-verified in the app container (imported via the Documents/Import flow); a passed on-device SwiftData CRUD smoke; DEBUG-assertion logs for image metadata, file protection, and deletion; and `MOBILE_PRECHECK.md`.

**Gate — read `MOBILE_PRECHECK.md` first. BOTH lines required:**
```
STARTER_CODE_ALLOWED: YES
STATUS: GO
```
Missing or negative on either → stop and report. Then verify the REPO block (app AND test targets build; pinned package resolution; prompt/config constants) and PHONE block (staging bundle ID; E4B at recorded path with matching sha256; one warm analysis within the recorded envelope). Never uninstall the app, change the bundle ID, or update packages. E4B only. Scope is FINAL: build exactly what is specified; nothing is reinstated during the build regardless of progress; when in doubt, cut styling, never features or tests. Commit at each block's end with the app runnable; log judgment calls.

## Product (final scope)

Two tabs. Select a bowel-movement photo (REQUIRED to save); optionally set four symptom flags and a note; local Gemma E4B returns structured enum observations; the user reviews and corrects **labeled rows** and saves via an explicit reviewed-save action; History (text cards) + a minimal Detail screen is the gastroenterologist experience, on the phone, in Airplane Mode. Documentation support only — never diagnosis, cause, treatment, prognosis, risk, or reassurance. Do NOT build: symptom-only entries, pain/urgency/count fields, thumbnails, assembled sentences or any generated prose, camera, export/sharing, charts, search, accounts, model switching, cloud, background inference, post-save editing, diagnostics screens, filesystem fault frameworks, storage fallbacks, App Store/TestFlight work.

## Architecture (fixed)

SwiftUI + SwiftData.

- **InferenceService** (actor): one `Engine` per MOBILE_PRECHECK (`.gpu`, `visionBackend` as recorded — image input fails without it, `maxNumTokens` ~2048). Fresh `Conversation` per analysis; greedy decoding (`topK: 1`, minimal temperature). Message = `Content.imageFile(<draft path>)` + `Content.text(<prompt below>)`, or exactly the recorded input form. Protocol-typed; DEBUG `MockInferenceService` scripts malformed and slow responses.
- **ImageStore**: PHPicker only. sRGB re-draw (drops all metadata), ≤1024 px, JPEG ~0.8, to immutable file-protected `Drafts/<UUID>.jpg`. Drafts survive AI failure; deleted only on Clear, replacement, or after a successful save; launch sweep.
- **EntryStore** (SwiftData behind a protocol; DEBUG `FailingEntryStore`): `autosaveEnabled = false`. **Save sequence, exactly:** copy draft to `Images/<UUID>.jpg` → `insert(entry)` → `try modelContext.save()`. **On failure: `modelContext.rollback()`** (mandatory — without it the inserted object lingers and a retry creates a phantom/duplicate) → delete the copied image best-effort → retain the original draft and form state → show the error. **On success:** delete the original draft, then run the shared form reset (below). **Delete:** remove object → `try save()` → on throw: `rollback()`, keep image, keep entry visible, show a brief failure message; after success delete the image file, with a **DEBUG assertion that the file is gone**. **Launch reconciliation:** delete orphan images; mark missing-file entries "image unavailable."
- **SafetyRules**: pure function of the four flags.

**Async-state rule (final):** every photo-preparation operation and every analysis attempt has its own unique ID. Two picker operations cannot complete out of order (stale prep IDs are ignored). A retry on the same photo is a NEW attempt ID — draft UUID alone is not sufficient identity. Analyze and Save enable only after the draft is fully sanitized, written, and hashed. Analyze is disabled while an attempt runs. **On timeout: invalidate the attempt, but keep Save/Clear/replacement locked until engine cancellation or completion is confirmed** — the timer expiring does not mean the engine released the file. Results with stale attempt IDs are discarded. **The Save transaction is locked:** while a save runs, Analyze, Save, Clear, and replacement are all disabled. After a successful save, one shared reset function — also used by Clear — resets: current draft/path and preparation ID; analysis attempt and validated AI snapshot; reviewed fields and provenance state; symptom flags and note; date to the new-entry default; Save eligibility. **Photo replacement is transactional:** prepare and hash the NEW draft first, then swap state and delete the old draft; cancellation or failure leaves the old selection intact; stale preparation files are deleted immediately. The busy flag always resets on confirmed completion, error, or confirmed cancellation.

**Privacy plumbing:** `.completeFileProtection` on Images, Drafts, store + `-wal`/`-shm` (DEBUG-asserted in the final build). `isExcludedFromBackup` on Models only. Privacy line verbatim: "The app sends no journal data to its own server and provides no app-managed sync. iOS may include journal data in your device backup, depending on your settings." No networking code paths; no analytics.

**`Entry`:** id UUID; capturedAt Date; imageFilename String?; imageSHA256 String?; redBlood String?; blackTarry String?; dizziness String?; severePain String?; note String? (≤500); painScore Int?; urgency String?; bm24h Int? (schema-only, NO UI); provenance String (`manual`|`ai_unedited`|`ai_edited`); reviewedAt Date?; originalAIJSON String?; reviewedJSON String?; modelID String?; createdAt/updatedAt Date. nil = "not reported," never coerced, rendered "Not recorded."

## Tab 1 — New Entry

Badges both tabs: "Runs locally on this iPhone" / "Documentation only — not diagnosis". Photo picker (required); editable date-time defaulting to now; DisclosureGroup "Symptoms and context (optional)": yes/no/unsure segmented controls with NO default for red blood, black or tarry stool, dizziness or fainting, severe or worsening pain; note ≤500. Symptom values NEVER enter the prompt or Conversation. Buttons: "Analyze on this iPhone" (progress: "Analyzing on this iPhone — no network used"); save button titled "Save Entry" (no analysis → `manual`) or **"Save Reviewed Entry"** (analysis present; pressing it IS the review acknowledgment; stamp `reviewedAt`; `ai_unedited`/`ai_edited` by diff against the validated AI snapshot); "Clear". Safety card — fixed, non-blocking, iff any flag == "yes" (user-reported only; model output can NEVER trigger it; unsure/unanswered show nothing; no reassurance when absent): "Some of the symptoms you reported can require urgent medical assessment. This app cannot determine the cause or severity. Seek urgent medical care. Call emergency services for uncontrolled bleeding, fainting, chest pain, trouble breathing, or other severe symptoms."

**Review panel** (after analysis): **labeled, editable rows** — "Bristol type" (1–7/none), "Apparent color," "Form," "Red-appearing material," "Black/tarry appearance" — each labeled "AI-assisted observation." No sentences are generated anywhere. Unusable image → a fixed label row from `quality_issue` ("Image quality: too dark — assessment not possible").

## Inference contract — all-enum; prompt aligned with validator

Prompt (verbatim, as `Content.text`):

---
You are the visual documentation component of a private gastrointestinal journal. Classify this bowel-movement photograph into neutral, structured visual observations. The user will review your output before saving. You are not diagnosing, determining causes, giving advice, or judging safety.

Rules: report only visible features. Never diagnose or name any condition. Use only the allowed values below. Lighting, water, and camera processing can change apparent color. If the image is unclear or does not clearly show a bowel movement, set image_usable to false. Bristol reference: 1 hard lumps; 2 lumpy sausage; 3 sausage with cracks; 4 smooth soft sausage; 5 soft blobs; 6 mushy ragged; 7 watery.

Return ONLY JSON, no code fences, exactly these keys and no others. Valid example:
{"image_usable": true, "quality_issue": "none", "apparent_bristol_type": 4, "apparent_color": "brown", "form": "smooth_formed", "red_appearing_material": "not_observed", "black_tarry_appearance": "not_observed"}

Allowed values — quality_issue: none, too_dark, blurred, obstructed, too_far, not_target_image, other. apparent_color: brown, light_brown, dark_brown, green, yellow, orange, red_appearing, black_appearing, pale_or_clay_appearing, mixed, unable_to_assess. form: hard_lumps, lumpy_formed, cracked_formed, smooth_formed, soft_blobs, mushy, watery, mixed, unable_to_assess. red_appearing_material and black_tarry_appearance: not_observed, possible, apparent, unable_to_assess. apparent_bristol_type: integer 1–7, or null.

Consistency rules you must follow exactly: when image_usable is true, quality_issue must be "none". When image_usable is false: quality_issue must not be "none"; apparent_bristol_type must be null; and apparent_color, form, red_appearing_material, and black_tarry_appearance must all be "unable_to_assess".
---

**Validation:** strip accidental fences → `JSONSerialization` key-set check rejecting ANY unknown key → exact-value enum decode → Bristol range → the same cross-field rules both directions. ONE repair turn ("Your previous reply was not valid JSON with exactly the required keys, allowed values, and consistency rules. Errors: <errors>. Return only the corrected JSON."). Second failure → "AI analysis unavailable — you can still save this entry manually," draft intact. Never fabricate. **`originalAIJSON` stores ONLY the final validated response; rejected raw attempts are never persisted.**

## Tab 2 — History

Reverse-chronological TEXT cards: date/time, flags summary, reviewed Bristol + color. Tap → **Detail (minimal, required — never a cut target):** image; "You reported" (nil → "Not recorded"); by provenance — `manual`: "No AI analysis was saved," no AI section; else "AI-assisted observation, reviewed by you" as labeled rows, "(edited)" for `ai_edited`; model ID footnote. Swipe-to-delete with confirmation.

## Schedule (commit each block; FEATURE FREEZE at minute 95; nothing reinstated)

0–15 verify both gate lines + REPO/PHONE + one warm analysis. 15–40 shell + SwiftData + stores skeleton; empty History renders. 40–65 prompt + parser + review rows + async-state rule (attempt/prep IDs; save lock). 65–85 save/delete with copy-promote, BOTH rollback paths, and the shared reset + History cards + Detail. 85–95 four flags + note + safety card + swipe-delete. **Write and run each block's tests INSIDE that block; 95–120 strictly: RERUN the complete suite, fix failures, final commit.** Behind at minute 50 → trim Detail styling only; Detail itself, features, and tests are untouchable.

## Acceptance (95–120)

**Automated (fault injection = MockInferenceService + FailingEntryStore only):** (1) embedded example validates; (2) unknown-key rejected; (3) cross-field rules both directions; (4) repair then double-failure — draft survives, manual save possible, rejected raw not persisted; (5) async-state: enablement gated on draft readiness; Analyze locked during an attempt; **timeout invalidates the attempt while locks persist until confirmed completion; a same-photo retry gets a new attempt ID; out-of-order prep resolves by prep ID; stale attempt-ID results discarded**; (6) FailingEntryStore on save → `rollback()` leaves ZERO entries, original draft untouched, copied image cleaned; retry yields exactly ONE entry; (6b) successful save runs the shared reset and a second entry saves cleanly from the fresh form; a save in progress locks Analyze/Save/Clear/replacement; replacement cancellation leaves the old selection intact; (7) FailingEntryStore on delete → rollback, entry visible, image intact, message shown; (8) post-delete DEBUG assertion: image file absent; (9) launch reconciliation (orphan image; missing-file entry); (10) provenance transitions + `reviewedAt` only with analysis; (11) nil flags persist, render "Not recorded"; (12) SafetyRules truth table; (13) DEBUG assertions: saved image EXIF/GPS 0; protection classes on Images/Drafts/store/WAL/SHM.

**Operator checkpoints, exactly this order:** (14) Airplane Mode on → select prop → analyze → correct one field → Save Reviewed Entry → History shows it → Detail attribution correct; (15) force-quit → relaunch → entry still present; (16) delete → entry gone from History (file removal covered by assertion 8); (17) five consecutive analyses clean; (18) manual flow shows "No AI analysis was saved."

## Final report

Built-per-block; device/build; automated + operator results incl. failures; warm latency in rehearsal; judgment calls; confirmation the minute-95 freeze, the fixed scope, and the acceptance block were honored. Claim nothing not run on the physical phone or in DEBUG tests.
