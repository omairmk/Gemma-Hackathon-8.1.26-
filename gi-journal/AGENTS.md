# GI Journal runtime rules

## Commands

- Install: `make setup`
- Download models: `make model`
- Tests: `make test`
- The physical-Mac qualifying sequence is mandatory for **both** models, one at a time on port 8080: E4B first with `smoke_evidence_e4b.json`, then E2B with `smoke_evidence_e2b.json`. Do not skip E2B because E4B passed or appeared fast.
- For each model: start with `MODEL_KEY=<e4b-or-e2b> PORT=8080 scripts/start_model.sh`; read the real PID from `.model_logs/model-8080.pid`; validate the PID's exact workspace executable/model/host/port with `scripts/server_process.py`; and prove its complete listener set with `scripts/verify_socket.sh "$PID" 8080`.
- Run the full live smoke/discovery with `.venv/bin/python scripts/smoke_test_model.py --model-key <e4b-or-e2b> --pid "$PID" --evidence smoke_evidence_<e4b-or-e2b>.json`. Only after it passes, while that exact PID still listens, run `.venv/bin/python scripts/create_eligible_candidate.py --evidence smoke_evidence_<e4b-or-e2b>.json`.
- Before starting the next model, revalidate the old exact PID/process/socket, stop only that PID, and confirm it exited and released port 8080. After E2B qualification, perform the same exact validated stop so the selected model can cold-start during offline proof.
- Select an independently eligible E4B only when its validated `warm_seconds` is at most 60 seconds; otherwise select an independently eligible E2B. Never infer eligibility from model size, a server start, or an evidence filename. If neither candidate revalidates, stop with `NO-GO`.
- Run offline proof only for the selected candidate: `PRIMARY_MANIFEST="$PWD/.devdata_preflight/candidates/<selected>.json" scripts/offline_test.sh`. Do not toggle Wi-Fi manually. A PASS exists only after the script verifies Wi-Fi restoration.

## Privacy and safety invariants

- The model server is loopback-only. Always prove its listener with `scripts/verify_socket.sh "$PID" 8080`; its complete-set check uses PID-scoped `lsof` with mandatory `-a` semantics. Also use `scripts/server_process.py` to reject look-alike executable, model, host, or port arguments.
- No cloud calls or telemetry during serving: `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, `HF_HUB_DISABLE_TELEMETRY=1`, `DO_NOT_TRACK=1`; `httpx` uses `trust_env=False` and no redirects. Never use thinking or speculative-decoding flags.
- Model-derived observations and app text about them never say “blood,” diagnose, reassure, or recommend. User-attributed symptom displays may quote the user's own words.
- Data profiles: `.devdata` (build), `.devdata_demo` (sandbox rehearsal); `~/.gi_journal` and `~/.gi_journal_demo` are only for a user-run app. Tests use `tmp_path`.
- Tests, seeders, and maintenance scripts must refuse destructive operations outside an injected, canonical, marker-bearing profile. The app deletes only a validated marker-bearing profile.

## Phase ritual

After each slice: update `PLAN.md` → run `pytest -q` → commit. PRECHECK and reports must record only commands that actually ran. Smoke evidence and candidates are revalidated against current prompt/schema/request/fixture hashes; a stale or edited artifact must not unlock offline proof.
