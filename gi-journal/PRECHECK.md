STATUS: NO-GO

# Friday preflight evidence — 2026-07-31

## Diagnosis

The required models, schema, fixtures, and server launcher are prepared locally, but this Codex sandbox does not expose a Metal device to MLX. Both model-server launches terminated before opening a listening socket, so neither model reached schema, determinism, image-dependence, latency, or offline gates. No model is eligible and no primary can be declared.

This is an environment result, not a claim that the physical Apple Silicon Mac cannot run MLX. The logs specifically say: `[metal::load_device] No Metal device available. This typically occurs in headless, sandboxed, or virtualized macOS sessions where the GPU is not accessible.`

## Environment and pinned direct requirements

- Workspace-local CPython: 3.12.11, rebuilt against OpenSSL 3.5.2 (details and source hashes in `ENVIRONMENT.md`).
- `mlx-vlm==0.6.8`
- `gradio==6.22.0`
- `pydantic==2.13.4`
- `pillow==12.3.0`
- `pillow-heif==1.5.0`
- `httpx==0.28.1`
- `pytest==9.1.1`
- Schema test result before the hardening pass: `.venv/bin/python -m pytest -q` → `3 passed`.
- Schema test result after the first hardening pass: `.venv/bin/python -m pytest -q` → `9 passed`.
- Schema test result after offline-path hardening: `.venv/bin/python -m pytest -q` → `11 passed`.
- Test result after the second consistency pass: `.venv/bin/python -m pytest -q` → `14 passed`.
- Final root rerun after inline-schema and literal-loopback hardening: `.venv/bin/python -m pytest -q` → `15 passed`.
- Final rerun after evidence, exact-process, route, and Wi-Fi-restoration hardening: `.venv/bin/python -m pytest -q` → `18 passed`.
- Final rerun after model/PID transcript binding, snapshot-content fingerprinting, OS-tool isolation, exact route classification, and symlink-safe runtime writes: `.venv/bin/python -m pytest -q tests` → `33 passed`.

## Downloaded local artifacts

| Model | Revision | Resolved local snapshot | Verification level |
| --- | --- | --- | --- |
| `mlx-community/gemma-4-e4b-it-4bit` | `475b9088d29754a3379866cf5aeb6b41acd313c2` | `.hf_cache/models--mlx-community--gemma-4-e4b-it-4bit/snapshots/475b9088d29754a3379866cf5aeb6b41acd313c2` | not verified |
| `mlx-community/gemma-4-e2b-it-4bit` | `238767527555cb75a05732a84dff5d6ba0dd6809` | `.hf_cache/models--mlx-community--gemma-4-e2b-it-4bit/snapshots/238767527555cb75a05732a84dff5d6ba0dd6809` | not verified |

All serving is configured to use these local paths. The downloads are recorded in `model_downloads.json`; the cache is workspace-local and gitignored.

## Exact attempted server commands and listener evidence

E4B qualifying attempt:

```text
MODEL_PATH=/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-journal/.hf_cache/models--mlx-community--gemma-4-e4b-it-4bit/snapshots/475b9088d29754a3379866cf5aeb6b41acd313c2 PORT=8080 scripts/start_model.sh
```

This launches:

```text
/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-journal/.venv/bin/mlx_vlm.server --model /Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-journal/.hf_cache/models--mlx-community--gemma-4-e4b-it-4bit/snapshots/475b9088d29754a3379866cf5aeb6b41acd313c2 --host 127.0.0.1 --port 8080
```

PID `3671` terminated with the Metal error above. `lsof -nP -a -p 3671 -iTCP -sTCP:LISTEN` returned no listener.

E2B diagnostic attempt — **non-qualifying** because it used port 8081 rather than the required qualifying port 8080:

```text
MODEL_PATH=/Users/omairmkhan/Documents/Codex/2026-07-31/files-mentioned-by-the-user-gi/gi-journal/.hf_cache/models--mlx-community--gemma-4-e2b-it-4bit/snapshots/238767527555cb75a05732a84dff5d6ba0dd6809 PORT=8081 scripts/start_model.sh
```

PID `3698` terminated with the same Metal error. `lsof -nP -a -p 3698 -iTCP -sTCP:LISTEN` returned no listener.

`--host 127.0.0.1` is present in both commands, but loopback binding was not earned because no socket was created.

## Production-schema smoke and model selection

`scripts/smoke_test_model.py` is prepared with the frozen Appendix B system prompt, a fully inlined Pydantic JSON schema (no unresolved `$ref`/`$defs`), temperature `0`, and `httpx(trust_env=False, follow_redirects=False, timeout=120s)`. It requires literal `http://127.0.0.1:8080` before reading image bytes. For each image adapter, it first tries `seed: 0`; if the runtime rejects that request, it retries the **same adapter** without the seed before moving to the next adapter. The evidence records the exact accepted seeded or seedless template and working request JSON. It was **not run** because neither server started. Therefore there is no accepted request shape, output, warm latency, determinism evidence, or image-dependence evidence.

Determinism contract when smoke can run: exact duplicate JSON is preferred. If the runtime is not byte-for-byte reproducible, all structured assessment and visible-observation enums/lists must still be identical; the evidence records either `exact_json` or `structured_enums_identical`. Evidence is written before discovery, after every request, and again on assertion failure. If both brown and green props report no relevant subject, the runner performs up to two retries using explicitly labeled stronger variants under ignored `.devdata_preflight/fixture_attempts/`; it never overwrites or silently changes the committed fixtures, and records every variant hash/output.

A primary runtime manifest is intentionally absent until a full smoke passes. While the exact qualifying PID still listens, `scripts/create_eligible_candidate.py` can create a selectable candidate bound to the pinned model/revision/path and full snapshot-content fingerprint, evidence-file SHA-256, current prompt/schema/request/fixture hashes, validated fixture results and determinism, warm latency, exact server executable/start-time/argv/socket proofs before and after smoke, winning adapter, and exact seeded/seedless template. The candidate creator rechecks the unchanged live identity/socket, and the offline manifest validator recomputes these bindings; minimal, internally inconsistent, edited, rebound, or stale evidence cannot establish eligibility. These local integrity checks are not cryptographic attestation against an operator who can rewrite code and recompute every local artifact. Offline mode reproduces the earned template in exactly one qualifying request and performs no adapter rediscovery.

The generated fixtures are `data/demo/synthetic_brown_clay_prop.png` and `data/demo/synthetic_green_clay_prop.png`, each 900×600 PNG and visibly watermarked `SYNTHETIC`.

Primary: none. E4B is not eligible; E2B is not eligible. Eligibility is blocked before inference, not overridden by latency.

## Offline and LM Studio

- Offline proof: not run. Qualifying port is fixed to 8080 in the candidate and `offline_test.sh`; any other `PORT` is rejected before network action. Before Wi-Fi discovery, the script revalidates the candidate, its evidence SHA-256, and the current contract hashes. It time-bounds external commands; accepts only an established no-default-route result rather than treating an arbitrary command error as offline proof; validates any live old PID's exact workspace executable, manifest-resolved model path, literal loopback host, and exact port before killing it; cold-restarts the selected model; and validates the new PID's exact process and complete listener set. It invokes exactly one request with the already-earned adapter/template. The complete-set parser was separately tested against a temporary `127.0.0.1:18080` listener: exact PID/port passed and a wrong port failed. The script prints PASS only after Wi-Fi has been restored and the restored state has been verified.
- Wi-Fi-off remains operator-only.
- LM Studio: not verified. It was optional and was neither installed nor downloaded.
- Fallback runtime: none verified; E2B is downloaded but not an eligible fallback.

## Mandatory physical-Mac qualifying sequence

1. Keep Wi-Fi on. Start E4B on port 8080; read its recorded PID; validate its exact workspace executable, pinned E4B snapshot, literal `127.0.0.1` host, and exact port with `scripts/server_process.py`; then prove its complete listener set with `scripts/verify_socket.sh`.
2. Run the full E4B smoke to the unique file `smoke_evidence_e4b.json`. Create `.devdata_preflight/candidates/e4b.json` only if that smoke passes and while the same validated PID still listens. Revalidate that exact process/socket, stop only that PID, and confirm it exited and released port 8080.
3. Regardless of E4B's outcome or latency, repeat the full qualifying process for E2B on port 8080 using `smoke_evidence_e2b.json` and, only after a pass, `.devdata_preflight/candidates/e2b.json`. Revalidate and stop the exact E2B PID after qualification so offline proof performs the required cold start.
4. Revalidate both available candidates. Select independently eligible E4B only if its validated `warm_seconds` is at most 60 seconds; otherwise select independently eligible E2B. If the required candidate does not independently revalidate, record `NO-GO`; never infer eligibility from a model download, server start, response, or filename.
5. Do not toggle Wi-Fi manually. Run exactly one selected-candidate proof with `PRIMARY_MANIFEST="$PWD/.devdata_preflight/candidates/<selected>.json" scripts/offline_test.sh`. Accept PASS only when the script itself proves no default route, cold restart, exact process/socket binding, one earned-template request, and verified Wi-Fi restoration.

The fully copyable command sequence and safe exact-PID stop checks are in `../assets/OPERATOR_GUIDES.md` §8.

## Scope and honesty

The runtime attempts occurred before the orchestrator's milestone commit; repository history records the final artifact state. No network-off test, model-server socket proof, model response, latency result, or GO claim was fabricated. The temporary HTTP listener used only to regression-test the socket parser is not model-runtime evidence.
