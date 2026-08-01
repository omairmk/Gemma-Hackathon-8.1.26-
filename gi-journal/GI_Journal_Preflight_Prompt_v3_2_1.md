# GI Journal — PROMPT A (v3.2.1): Friday Preflight

<!--
SETUP (from the folder where these two .md files are saved; use absolute source
paths if elsewhere):
  mkdir gi-journal
  cp GI_Journal_Preflight_Prompt_v3_2_1.md GI_Journal_Build_Prompt_v3_2_1.md gi-journal/
  cd gi-journal
  git init
Then, on home Wi-Fi:
  codex --sandbox workspace-write \
        -c 'sandbox_workspace_write.network_access=true' \
        -c model_reasoning_effort=high
and paste this file. Interactive is recommended tonight — approve prompts (Wi-Fi
toggle, optional LM Studio). Model: CLI default or 5.6 Sol. Broad network access
is deliberate tonight (pip + model downloads); Saturday's prompt tightens to a
loopback-only proxy. This prompt ENDS in exactly one of two committed terminal
states: PRECHECK.md `STATUS: GO`, or an honest `STATUS: NO-GO` with diagnosis.
-->

You are a senior engineer preparing an Apple Silicon Mac (macOS, Python 3.11+) for a one-day healthcare hackathon build tomorrow. Tonight's sole objective: a verified, committed, offline-capable local model runtime plus the project skeleton the Saturday prompt assumes. Do not build product features.

**This repo contains `GI_Journal_Build_Prompt_v3_2_1.md` (the Saturday prompt). Read its Appendix A (analysis schema) and Appendix B (image system prompt) — tasks below depend on them. If the file is missing, stop and ask for it.**

**Sandbox note:** keep every write inside this workspace. `HF_HOME=$PWD/.hf_cache` (gitignored) for model downloads; `$PWD/.devdata*` (gitignored) for runtime data. Do not write outside the repo tonight (`--add-dir` exists if something truly requires it; prefer not).

## Tasks

1. **Environment.** `.venv`; install and pin in `requirements.txt`: `mlx-vlm`, `gradio`, `pydantic`, `pillow`, `pillow-heif` (drop if it won't install cleanly), `httpx`, `pytest`. `.gitignore` now: `.env`, `.venv`, `__pycache__`, `.hf_cache/`, `.devdata*/`, `*.db*`, exports, Gradio temp.

2. **Skeleton the Saturday prompt assumes.** `Makefile` (`setup`, `model`, `run` placeholder, `test`); `PLAN.md` phase checklist; `schemas.py` implementing the build prompt's Appendix A exactly (Pydantic v2, `extra="forbid"`, Literals, cross-field validator); `tests/test_schemas.py`: valid example validates, unusable cross-field rules enforce, invalid enum rejects. `pytest -q` green tonight.

3. **Model download, pinned, in-workspace.** With `HF_HOME` set, download BOTH `mlx-community/gemma-4-e4b-it-4bit` (~5.2 GB) and `mlx-community/gemma-4-e2b-it-4bit`, recording revision hashes and resolved local snapshot paths. All serving uses LOCAL PATHS — nothing may depend on the Hugging Face hub at the venue.

4. **Server, loopback-only, PID-bound.** `scripts/start_model.sh`: sets `HF_HOME`, `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`; starts `mlx_vlm.server --model <local_path> --host 127.0.0.1 --port 8080`; records the launched PID. `--host 127.0.0.1` is mandatory (documented default is `0.0.0.0`). No `--draft-model`/speculative flags (incompatible with structured outputs); no thinking flags (Gemma 4 thinking is off by default). Verify the socket for that PID — note the `-a` to AND the criteria, since `lsof` ORs them by default:
   `lsof -nP -a -p "$PID" -iTCP -sTCP:LISTEN`
   must show loopback:8080 for that PID and nothing else.

5. **Smoke test — production schema, deterministic, image-dependence proven.** `scripts/smoke_test_model.py`:
   - Fixtures (Pillow-generated, watermarked SYNTHETIC; commit the tiny PNGs to `data/demo/`): two unmistakably stool-like synthetic clay-style props with simple 3D shading on neutral backgrounds — one BROWN, one GREEN. Abstract shapes would legitimately classify as "no relevant subject" and cause a false NO-GO; the props must be recognizable as staged stool simulacra while obviously fake.
   - Requests: the build prompt's Appendix B system prompt, `response_format` json_schema derived from `schemas.py` (flatten `$ref`s if needed), **temperature 0**, fixed seed if supported. httpx `trust_env=False`, `follow_redirects=False`, read timeout ~120 s. Determine the accepted image-content shape empirically — try (i) OpenAI-style base64 `image_url`, (ii) mlx-vlm `input_image` with a local path, (iii) `image_url` with a local path; wrap the winner in one adapter and record the exact working request template JSON.
   - Assertions, per model: every response parses and validates; **determinism control** — the brown prop sent twice yields identical JSON (near-identical with identical enums if the runtime is not exactly reproducible); **image dependence** — BOTH props report `contains_relevant_subject: true`, and `primary_color` lands in a brown family (brown/light_brown/dark_brown) for the brown prop vs green for the green prop. If both props come back "no relevant subject," improve the prop rendering (stronger shading/contrast) and retry up to twice; still failing → that model is ineligible. Record all outputs (abbreviated) and warm seconds/image.
   - Run against E4B, then E2B. A model appears in PRECHECK only with the verification level it actually earned.

6. **Declare the primary — eligibility first — and prove it offline.** A model is ELIGIBLE only if it passed every §5 assertion (schema, determinism, image dependence). Primary = eligible E4B if warm latency ≤ ~60 s/image; else eligible E2B; if neither is eligible, that is `STATUS: NO-GO` — latency never overrides eligibility. `scripts/offline_test.sh`: detects the Wi-Fi device from `networksetup -listallhardwareports` (never hard-code en0); `trap` restores Wi-Fi on ANY exit; timeouts on every step; runs as ONE command: Wi-Fi off → **verify no external route remains** (`route -n get default` must fail — Ethernet, VPN/utun, or phone tethering would defeat the test; if a route remains, stop and report it) → kill server → cold-start from local path → **re-run the §4 PID-bound socket proof on the NEW pid** → one smoke request against the declared primary → Wi-Fi on. Only this counts as offline proof, and it attaches to the primary; the other model is `verified-smoke-only` unless also run offline.

7. **Optional, last, time-permitting — LM Studio.** Only if the LM Studio APPLICATION AND the exact model `lmstudio-community/gemma-4-E4B-it-MLX-4bit` are ALREADY on disk (never install or download either): start per `lms server start --help` (approvals fine), then the full bar: PID-bound loopback socket check with `-a` (record the actual port — do not assume 1234), production-schema smoke with the §5 assertions, offline restart. All three or PRECHECK records `LM Studio: not verified`. Skipping is acceptable: record `no fallback runtime — E2B is the fallback model`.

8. **AGENTS.md** (≤1 page): run/test commands; privacy invariants (loopback-only model URL AND PID-bound `-a` socket verification; no cloud calls; no telemetry; `trust_env=False`; no thinking/spec-dec flags); language rules — model-derived observations and app text about them never say "blood"/diagnose/reassure, while symptom questions and user-attributed displays may use the user's own words ("You reported: red blood — yes"); phase ritual "update PLAN.md → `pytest -q` → commit"; data profiles (`.devdata` build, `.devdata_demo` sandboxed rehearsal, `~/.gi_journal` and `~/.gi_journal_demo` user-run only); tests in `tmp_path`; destructive-op refusal of non-injected dirs applies to tests, seeders, and maintenance scripts (the app itself deletes only a validated, marker-bearing profile — see the build prompt).

9. **PRECHECK.md — the Saturday contract.** First line `STATUS: GO` or `STATUS: NO-GO`. Record: Python + pinned versions; ELIGIBILITY result per model with evidence (schema/determinism/image-dependence outputs, abbreviated); declared primary (model, local path, revision) and why; exact server command + PID + `-a` socket evidence; exact request template and which image shape won; warm latency per model; per-model verification level (`verified-full` = smoke + offline / `verified-smoke-only` / `not verified`); LM Studio status; offline result incl. the no-default-route check; anomalies and workarounds.

10. **Terminal states.** Time-box runtime debugging to ~45 minutes total. All gates passed → commit `preflight: STATUS GO — verified local Gemma 4 runtime`. Otherwise → PRECHECK with `STATUS: NO-GO`, the failing gate, evidence, and the two most promising manual next steps; commit `preflight: STATUS NO-GO — <short reason>`. A committed honest NO-GO is a successful run of this prompt; an uncommitted or dishonest GO is not.

## Report back
The STATUS line and why; exact working commands; request template; latencies; eligibility, PID/socket, determinism, image-dependence, and route-check evidence; offline result; fallback labels — claiming nothing you did not run.
