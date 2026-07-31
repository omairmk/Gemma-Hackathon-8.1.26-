# Operator guides — event queue

**PRIVATE OPERATOR HANDOFF:** this guide contains organizer-provided intake links. Do not publish it; remove those links and local identifiers from any public copy.

Each guide is deliberately executable without improvising. Time is an estimate excluding waits/downloads. Stop rather than guessing when a stated condition fails; capture the listed evidence and return it to the build operator.

## 1. Starter-code rules question — 3 minutes

**Do:** Open the event Discord → the rules/help channel → paste exactly: `Are teams allowed to arrive with a custom Swift starter app that already performs local image inference and includes basic persistence and test scaffolding, or may we only preinstall tools, dependencies, and model files?` → Send. If a moderator replies, screenshot the reply and copy its permalink/text into **[evidence location]**.

**Expected:** A written moderator answer, or a timestamped unanswered question. **Stop:** Do not begin use of prebuilt app code until the answer is “yes” or the event’s published rules independently allow it. **Evidence:** screenshot/permalink and timestamp. **Unblocks:** `STARTER_CODE_ALLOWED`.

## 2. Building access and Cerebras forms — 6 minutes

**Do:** The One WTC security-list deadline has passed and completion is unverified. Open the organizer email titled **“New message in Build with Gemma NYC: On-Device AI for Healthcare”** and inspect its latest [One WTC security-list form](https://forms.gle/bt7woPmo48GnQ1tw7). If it shows an existing response or confirmation, capture that state; if it is closed or no confirmation can be established, capture the page and notify the organizer immediately. Do not submit a duplicate or claim that an earlier submission was missed. Open **“Action needed: register for Cerebras credits by Friday 8PM”** and use the [Cerebras credits form](https://forms.gle/6i9a32hUhfWa2aQ68); submit before Friday 8:00 PM ET. Save every on-screen confirmation because a receipt email is not guaranteed.

**Expected:** One WTC shows either verifiable confirmation/existing-response evidence or a captured closed/unverified state ready for organizer follow-up; Cerebras shows a submission confirmation. **Stop:** If a form is unavailable, asks for unexpected sensitive information, or no longer accepts responses, capture the page and notify the organizer; do not invent a submission or non-submission. **Evidence:** confirmation/state screenshots and timestamps (avoid showing secrets). **Unblocks:** event attendance/credits logistics only to the extent the organizer confirms it.

## 3. Accept the Xcode license — before any device work — 5 minutes

**Do:** Open Terminal. Run `sudo xcodebuild -license accept`. Enter the Mac administrator password only in Terminal when prompted (it will not display). Then run `xcodebuild -version`. Open Xcode once; if macOS shows an additional-component prompt, click **Install** and wait for completion.

**Expected:** `xcodebuild -version` prints an Xcode version/build and Xcode opens without a license dialog. **Stop:** If the command reports Xcode is missing, the license is still not accepted, credentials are unavailable, or component installation fails. Do not proceed to phone signing. **Evidence:** sanitized terminal screenshot showing version and successful command exit; screenshot of any error. **Unblocks:** device build/signing.

## 4. Connect, trust, sign, and first-build the iPhone — 12 minutes

**Do:** Connect the unlocked iPhone by cable. On iPhone, tap **Trust** if prompted and enter the device passcode. In Xcode, open `gi-timeline/GITimeline.xcodeproj` (or the recorded workspace), select the **GITimeline** scheme, then select the named iPhone in the destination menu. Select the project → **GITimeline target** → **Signing & Capabilities** → choose the operator’s Team; allow Xcode to manage signing if that is the project’s selected configuration. Click Run (▶).

**Expected:** Xcode reports `Build Succeeded` and launches GITimeline on the phone. **Stop:** If the device is absent, untrusted, locked, developer mode/signing/profile approval fails, bundle ID conflict appears, or build fails. Do not change bundle ID, update packages, uninstall the app, or “fix” signing by deleting profiles without build-owner direction. **Evidence:** Xcode build result screenshot, destination/device name, and exact error text if failed. **Unblocks:** physical iPhone gates.

## 5. AI Edge Gallery viability check — 9 minutes

**Do:** First validate the listing from a primary source—do not rely on App Store search ranking. In Safari, type `https://ai.google.dev/edge/gallery` yourself and confirm the address bar remains on Google’s `ai.google.dev` domain. Follow Google’s iOS/App Store link, if offered. Confirm the destination is an Apple `apps.apple.com` page, and capture the app name, displayed developer, URL, and date. Only then tap **View in App Store** → **Get** → authenticate/install. If the official Google page does not currently offer an iOS/App Store link, stop and ask the build owner for a current official Apple or Google link; do not guess a publisher or install a look-alike. After a validated installation, open the app, choose **Ask Image**, select the brown synthetic prop, run once, and capture the visible result/status.

**Expected:** An official Google page leads to an Apple-hosted listing, the validated app installs, and Ask Image completes a run using the brown prop. **Stop:** If either domain is wrong, no official iOS link exists, the listing changes between pages, the app is unavailable, the prop cannot be selected, or the run fails. Do not treat search results or installation alone as identity/vision evidence. **Evidence:** Google source URL, Apple listing URL plus displayed developer/date, selected image, and result/error screenshots. **Unblocks:** device-viability evidence only.

## 6. Import verified E4B model — 10 minutes plus transfer time

**Do:** Before copying, in Finder select the exact preverified E4B artifact → **File → Get Info** and record its size in bytes/GB. Double that number. On iPhone open **Settings → General → iPhone Storage** and wait for the storage calculation to finish. If the screen shows “used of total,” subtract used from total to calculate Available; otherwise record the displayed Available value. Continue only when Available is at least 2× the artifact size; this headroom covers both the staged copy and verified promoted copy during import. Then in Finder select the connected iPhone → **Files** → locate the GITimeline Documents area → drag the artifact into `Documents/Import` (create/select only if the app’s documented import flow exposes it). Disconnect only after transfer completes. On iPhone open GITimeline → open the app’s import control → select the staged artifact → confirm import. Compare the app’s displayed verified SHA-256 banner to the recorded expected SHA-256 in `MOBILE_PRECHECK.md`.

**Expected:** Recorded Available space is ≥2× artifact size, the app reports a successful import, and the displayed hash exactly matches the recorded hash. **Stop:** If free space is <2×, free space safely before retrying; do not stage/import and do not delete unrelated data without the owner’s approval. Also stop if no app container is visible, transfer is partial, the file name/model differs, the banner is missing, or hashes differ. Do not analyze or replace the artifact. **Evidence:** artifact Get Info, iPhone Storage Available value and calculation, Finder transfer completion, app import result, and both hash values. **Unblocks:** engine bring-up.

## 7. Physical iPhone gate and acceptance session — 35–50 minutes

**Do — preflight gates, in this exact order:** (1) verify the model ID, path, artifact size, and SHA-256 against `MOBILE_PRECHECK.md`; (2) analyze the brown synthetic prop, then the contrasting green synthetic prop, and capture both structured outputs; (3) analyze the same brown prop again and record whether its validated structured output matches the first brown run under the recorded deterministic settings; (4) run five consecutive warm analyses and record each latency. While they run, in Xcode choose **View → Navigators → Show Debug Navigator**, select the running GITimeline process, watch **Memory**, and record/capture the highest observed value as peak memory; (5) execute the on-device SwiftData create/read/update/delete smoke and capture the actual result; (6) exercise the required draft lifecycle checks, including draft retention after failed/skipped analysis and cleanup on Clear/replacement/successful save as the precheck directs; (7) in Xcode choose **View → Debug Area → Activate Console** and capture the required DEBUG logs/assertions for sanitized image metadata, file protection (Drafts, Images, store, WAL/SHM), rollback/deletion, and post-delete file absence. Do not advance to acceptance if a required preflight gate fails or remains blank.

**Do — operator acceptance, in this exact order:** (14) enable Airplane Mode (**Settings → Airplane Mode** on) → select a synthetic prop → analyze → correct one field → tap **Save Reviewed Entry** → verify the card in **History** → open **Detail** and verify attribution; (15) force-quit (App Switcher → swipe GITimeline up) → relaunch → verify the entry persists; (16) delete the entry → verify it is gone from History; (17) perform five consecutive analyses and record whether all five complete cleanly; (18) perform a fresh manual flow without analysis and verify Detail says exactly **“No AI analysis was saved.”** Restore connectivity only after evidence capture if desired.

**Expected:** Fill only observed values in `MOBILE_PRECHECK.md`; a failure is a valid NO-GO. **Stop:** On model/hash mismatch, non-contrasting or non-repeatable behavior where the precheck requires it, unexpected network requirement, crash, missing peak-memory/latency record, failed CRUD/draft/DEBUG check, failed persistence/deletion, wrong attribution/manual-flow text, or any claim the operator cannot observe. Do not reorder acceptance, skip a failure, or fill blanks optimistically. **Evidence:** completed precheck; both contrasting outputs and repeated-brown comparison; five warm latencies and peak memory; CRUD/draft results and DEBUG logs; screenshots/video of Airplane Mode, reviewed-save, History/Detail, relaunch, deletion, five clean analyses, and manual Detail text; exact failures. **Unblocks:** `STATUS: GO` only when every required gate genuinely passes.

## 8. Mac dual-model qualification and one-command Wi-Fi-off check — 20–35 minutes

**Do — keep Wi-Fi on for all qualification steps:** From the repository root run `cd gi-journal`. Qualify **both** models sequentially on the only qualifying port, 8080: E4B first and E2B second. E4B passing or appearing fast never permits skipping E2B.

Start and qualify E4B:

```sh
E4B_MODEL="$PWD/.hf_cache/models--mlx-community--gemma-4-e4b-it-4bit/snapshots/475b9088d29754a3379866cf5aeb6b41acd313c2"
MODEL_KEY=e4b PORT=8080 scripts/start_model.sh
IFS= read -r E4B_PID < .model_logs/model-8080.pid
.venv/bin/python -I scripts/server_process.py --pid "$E4B_PID" --model "$E4B_MODEL" --port 8080
scripts/verify_socket.sh "$E4B_PID" 8080
if .venv/bin/python -I scripts/smoke_test_model.py --model-key e4b --pid "$E4B_PID" --evidence smoke_evidence_e4b.json; then
  .venv/bin/python -I scripts/create_eligible_candidate.py --evidence smoke_evidence_e4b.json
else
  echo "E4B did not earn a candidate; preserve smoke_evidence_e4b.json and continue to E2B."
fi
```

Before E2B, revalidate and stop only the exact E4B process; never kill a PID that fails either validation:

```sh
if kill -0 "$E4B_PID" 2>/dev/null; then
  .venv/bin/python -I scripts/server_process.py --pid "$E4B_PID" --model "$E4B_MODEL" --port 8080
  scripts/verify_socket.sh "$E4B_PID" 8080
  kill "$E4B_PID"
fi
STOP_WAIT=0
while kill -0 "$E4B_PID" 2>/dev/null && [ "$STOP_WAIT" -lt 15 ]; do
  /bin/sleep 1
  STOP_WAIT=$((STOP_WAIT + 1))
done
if kill -0 "$E4B_PID" 2>/dev/null; then echo "STOP: validated E4B PID did not exit." >&2; false; fi
if /usr/sbin/lsof -nP -iTCP:8080 -sTCP:LISTEN; then echo "STOP: port 8080 was not released." >&2; false; fi
```

Then start and independently qualify E2B on the same port with its own evidence and candidate:

```sh
E2B_MODEL="$PWD/.hf_cache/models--mlx-community--gemma-4-e2b-it-4bit/snapshots/238767527555cb75a05732a84dff5d6ba0dd6809"
MODEL_KEY=e2b PORT=8080 scripts/start_model.sh
IFS= read -r E2B_PID < .model_logs/model-8080.pid
.venv/bin/python -I scripts/server_process.py --pid "$E2B_PID" --model "$E2B_MODEL" --port 8080
scripts/verify_socket.sh "$E2B_PID" 8080
if .venv/bin/python -I scripts/smoke_test_model.py --model-key e2b --pid "$E2B_PID" --evidence smoke_evidence_e2b.json; then
  .venv/bin/python -I scripts/create_eligible_candidate.py --evidence smoke_evidence_e2b.json
else
  echo "E2B did not earn a candidate; preserve smoke_evidence_e2b.json."
fi
```

Revalidate and stop the exact E2B process before selection so the selected model must cold-start inside offline proof:

```sh
if kill -0 "$E2B_PID" 2>/dev/null; then
  .venv/bin/python -I scripts/server_process.py --pid "$E2B_PID" --model "$E2B_MODEL" --port 8080
  scripts/verify_socket.sh "$E2B_PID" 8080
  kill "$E2B_PID"
fi
STOP_WAIT=0
while kill -0 "$E2B_PID" 2>/dev/null && [ "$STOP_WAIT" -lt 15 ]; do
  /bin/sleep 1
  STOP_WAIT=$((STOP_WAIT + 1))
done
if kill -0 "$E2B_PID" 2>/dev/null; then echo "STOP: validated E2B PID did not exit." >&2; false; fi
if /usr/sbin/lsof -nP -iTCP:8080 -sTCP:LISTEN; then echo "STOP: port 8080 was not released." >&2; false; fi
```

Revalidate each candidate that exists with `.venv/bin/python -I scripts/primary_manifest.py --manifest .devdata_preflight/candidates/e4b.json` or the corresponding `e2b.json`. This recomputes the evidence-file hash, frozen-contract hashes, full model-snapshot content fingerprint, before/after process identity/socket proofs, fixture/result and determinism assertions, latency binding, and pinned model binding; file existence alone is not eligibility. Choose validated E4B only when its validated `warm_seconds` is at most 60 seconds. Otherwise choose validated E2B. If the required candidate is absent or fails revalidation, stop and record `NO-GO`.

**Do — selected candidate only:** Do not toggle Wi-Fi manually. Run exactly one qualifying offline command, substituting only the selected validated candidate name:

```sh
PRIMARY_MANIFEST="$PWD/.devdata_preflight/candidates/e4b.json" scripts/offline_test.sh
```

Use `e2b.json` instead only when the selection rule chose eligible E2B. The script revalidates the candidate before discovering or changing Wi-Fi, installs a restore trap, turns Wi-Fi off, requires an established no-default-route result, cold-restarts the selected local model, validates the new PID's exact workspace executable/model/host/port and exactly `127.0.0.1:8080 (LISTEN)`, makes one request with the already-earned template, restores Wi-Fi, verifies the restored state, and only then prints PASS. Never bypass a refusal.

**Expected:** Two distinct full-smoke evidence files, zero to two independently earned candidate files, a rule-selected and revalidated primary, and—only if offline proof succeeds—a zero exit plus the script's PASS line, one saved `offline_smoke_evidence.json`, exact new-PID process/loopback proof, established no-default-route result, one earned-template request, and verified Wi-Fi restoration. Success must not be inferred from a server start, localhost URL, evidence filename, candidate filename, or Wi-Fi toggle alone. **Stop:** If either mandatory smoke is skipped, an old PID cannot be exactly validated/stopped, port 8080 remains occupied, selection would require inferred eligibility, the candidate is missing/unverified, another default route remains, route absence cannot be established, the test needs a download/external service, the server/request fails, Wi-Fi restoration is not verified, or any step times out. Preserve exact output and record `NO-GO`. **Evidence:** both smoke files, available candidate files, selection rule and warm latency, terminal command/output, Wi-Fi-off/on screenshots, route result, PID-bound exact process/loopback evidence, one-request result, selected candidate path, and timestamp. **Unblocks:** Mac offline gate only when every scripted step passes.
