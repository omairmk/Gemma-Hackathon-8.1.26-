# GI Hackathon handoff

Updated: 2026-07-31 12:42 EDT

This is a **private operator handoff**, not a public-release package. No track has earned an on-device/offline `GO`. The exact organizer form links and local identifiers must be removed from any future public copy.

## Track state

### Track A — iPhone candidate: code-ready; upstream/operator blocked

- The native SwiftUI/SwiftData starter, test target, exact remote LiteRT-LM `v0.14.0` pin, `Package.resolved`, model importer, local inference service, two tabs, rollback paths, safety rules, and synthetic fixtures are present. Track A milestone commit: `ef191d4`.
- Root verification: 14/14 host-core tests pass. A temporary, non-committed overlay using the exact `v0.14.0` source/API with only the official release-asset checksums corrected passes 11/11 arm64 iPhone-simulator app tests.
- The committed exact remote package does **not** resolve. The `v0.14.0` tag manifest's declared iOS/macOS checksums differ from the assets currently served by the same official release. No dependency workaround is committed; using the later upstream checksum correction requires explicit authorization because it departs from the frozen exact-tag instruction.
- `STARTER_CODE_ALLOWED`, `STATUS`, every phone field, and every physical gate in `gi-timeline/MOBILE_PRECHECK.md` remain blank. No signed phone build, E4B import/inference, latency/memory result, protection log, CRUD/device persistence, or Airplane-Mode proof is claimed.

### Track B — Mac fallback: honest `STATUS: NO-GO`; operator continuation ready

- Workspace Python 3.12.11, pinned direct requirements, schema, prompts, fixtures, loopback launcher, smoke/evidence runner, eligible-candidate creator, and single-command offline proof are prepared.
- Track B's frozen honest state is committed as `3056ea5` (`preflight: STATUS NO-GO — Metal unavailable in sandbox`).
- Local E4B and E2B snapshots are present at the recorded revisions but are ignored and excluded from Git/archive. Both server attempts terminated before binding because this Codex sandbox exposes no Metal device. No socket, response, accepted adapter, eligibility, latency, primary, or offline result is claimed.
- Root verification: 33/33 tests pass; Python compilation and shell syntax pass. Missing-manifest, wrong-port, minimal/tampered/rebound/stale evidence, ambiguous route results, and look-alike process bindings refuse safely in the tested paths. The smoke path requires literal `127.0.0.1:8080`, records the actual executable/start time/argv/socket before and after, binds a full model-snapshot content fingerprint, records an earned seeded/seedless template and failure evidence, and uses up to two non-destructive fixture retries. Candidate/offline validation recomputes those bindings plus fixture/result assertions, determinism, and latency. The offline path uses exactly one earned-template request. No live MLX process or Wi-Fi operation was run by these tests.
- Continue on the physical Apple Silicon Mac from `gi-journal/PRECHECK.md`. Wi-Fi stays on while the operator runs the mandatory full qualifying smoke for E4B and then E2B, each on port 8080 with unique evidence and candidate files. Stop and validate each exact PID safely between models. Select eligible E4B only when its validated warm latency is at most 60 seconds; otherwise select independently eligible E2B. Only `scripts/offline_test.sh` toggles Wi-Fi, and it prints PASS only after verified restoration.

### Track C — event assets complete; publication blocked

- Private operator guides, two 90-second demo variants, Kaggle writeup skeleton, public-readiness checklist, claim controls, and fixture provenance are present.
- Do **not** publish yet. The owner must select a repository license; model/runtime/transitive notices must be verified; live organizer form links, local paths, and personal bundle identifiers need a sanitized public copy. Model weights and local environments are not in Git.

## Operator queue and exact continuation

Work in order where dependencies require it. Full instructions and the private form links are in `OPERATOR_QUEUE.md` and `assets/OPERATOR_GUIDES.md`.

| Item | Operator action | Estimate | Current state | What Codex does immediately after completion |
|---|---|---:|---|---|
| 0 | Accept Xcode license | done | **DONE** | No further action; the local toolchain result is already recorded. |
| 1 | Post the exact starter-code question in event Discord; return moderator text/permalink | 3 minutes plus reply wait | **NOT STARTED** | Record the answer verbatim in `MOBILE_PRECHECK.md`. If allowed, retain Track A as the candidate; if disallowed, do not use the prebuilt starter and route the demo to Track B. No inference from silence. |
| 2 | Verify the One WTC form state and complete Cerebras; save confirmation screens | 5–10 minutes | **One WTC deadline passed; completion unverified. Cerebras urgent.** | Record only the confirmation state/timestamp. If the One WTC form is closed or no confirmation can be established, preserve the page state and draft the organizer follow-up; never claim submission or non-submission without evidence. |
| 3 | Authorize an upstream-checksum decision if starter code is allowed; then connect/trust/sign/build the iPhone | 10–20 minutes | **BLOCKED on item 1 and checksum decision** | With explicit authorization, apply the narrow upstream dependency correction, resolve the package, rerun host/simulator tests, and commit the deviation. Then validate the operator's signed-build output, fill only observed PHONE fields, and queue the remaining device gates. |
| 4 | Validate/install AI Edge Gallery from an official source; run Ask Image on the brown prop | 10–20 minutes plus download | **NOT STARTED** | Record app identity, listing URL/date, selected fixture, result/error, and latency as independent device-viability evidence only; never treat it as GITimeline evidence. |
| 5 | Obtain the exact non-`-web` E4B `.litertlm`, provide its path/hash, then transfer/import it | 10–30 minutes plus download/transfer | **BLOCKED on artifact/auth and item 3** | Validate filename/model identity and SHA-256, write the expected hash into `MOBILE_PRECHECK.md`, compare it to the in-app verified-hash banner, and stop on any mismatch before inference. |
| 6 | Run the guided phone gates and Track B physical-Mac continuation/offline command | 35–50 minutes phone; 20–35 minutes Mac | **PARTIALLY READY** | Validate raw logs/evidence, fill only observed precheck cells, choose the eligible primary by the frozen eligibility/latency rule, and set each track to `GO` only if every required gate passes; otherwise preserve an honest `NO-GO`. Then select the matching demo script and evidence-backed Kaggle wording. |

Track B requires both `smoke_evidence_e4b.json` and `smoke_evidence_e2b.json` from separate sequential full smokes on port 8080. A candidate is created only for an independently passed smoke while its exact process/socket is live. After both attempts, Codex revalidates available candidates and applies the frozen rule: eligible E4B with validated warm latency ≤60 seconds, otherwise independently eligible E2B. Only the selected printed candidate path may be used for the one-command Wi-Fi-off proof. A candidate is not an offline result.

## Risks and decisions still open

- One WTC's Friday 12:00 PM ET organizer deadline has passed and completion remains unverified; that does not establish that a submission was missed. Cerebras is due Friday 8:00 PM ET.
- Starter-code permission is unknown. The existing app must not be used at the event until the written rule answer permits it.
- The official LiteRT-LM `v0.14.0` release is internally inconsistent today; silent repinning would violate the frozen contract.
- The Codex sandbox has no MLX Metal device. Track B may work on the physical Mac, but only the unrun smoke/offline gates can establish that.
- The exact mobile E4B artifact and verified SHA-256 are absent; model-provider terms/auth may require the operator.
- Phone-only signing, model load, memory/latency, device file protection, persistence, deletion, and Airplane-Mode checks remain unrun.
- Public release is blocked by owner license selection, verified third-party/model notices, and private-data sanitization. Keep this archive private.

## One-screen summary

- **Do now:** inspect and capture the One WTC form/confirmation state; contact the organizer if it is closed or cannot be verified. Complete Cerebras before 8:00 PM ET and save its confirmation.
- **Next unblock:** return the Discord moderator answer verbatim.
- **Track A:** committed candidate; 14 host + 11 simulator tests pass; exact remote pin and all phone gates are blocked/unrun.
- **Track B:** committed `NO-GO` at `3056ea5`; 33 tests pass; mandatory E4B-then-E2B physical-Mac smoke/candidate selection and selected-candidate offline proof are ready but unrun.
- **Track C:** private event materials are ready; public publication is not.
- **Claims:** no on-device, offline, eligibility, physical-device, form-submission, or public-readiness claim has been made without evidence.
