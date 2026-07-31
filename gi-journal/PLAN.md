# Friday preflight plan

- [x] Recover and read frozen Prompt A and Prompt B appendices.
- [x] Start local Python 3.12 installation (workspace-only).
- [x] Create `.venv`, install the required runtime, and pin `requirements.txt`.
- [x] Generate production schema and run schema tests.
- [x] Generate watermarked synthetic fixtures.
- [x] Download E4B and E2B locally with revisions and snapshot paths.
- [x] Attempt loopback-only server start for E4B and E2B; both failed before binding because this sandbox exposes no Metal device.
- [ ] Run the full production-schema, deterministic, image-dependence smoke for **both** models sequentially on port 8080—E4B first with `smoke_evidence_e4b.json`, then E2B with `smoke_evidence_e2b.json`—and create a candidate only for each independently passed smoke (blocked: no MLX server).
- [ ] After both qualifying attempts, select eligible E4B only if its validated warm latency is at most 60 seconds; otherwise select independently eligible E2B. Run the one-command operator offline proof only for that selected candidate (blocked: no eligible model in this environment).
- [x] Harden smoke evidence: loopback/8080 enforcement, seed fallback recording, incremental failure records, and two non-destructive fixture retry variants.
- [x] Add a socket/PID/model/template-bound eligible-candidate creator for operator selection before offline proof.
- [x] Revalidate evidence SHA-256, frozen-contract hashes, fixture bindings/results, determinism, warm latency, and exact process argv/socket before a candidate can unlock offline proof.
- [x] Make offline route checks fail closed on ambiguous command errors and print PASS only after Wi-Fi restoration is successful and verified.
- [x] Write factual PRECHECK.md and update AGENTS.md.

Current status: `STATUS: NO-GO` for this sandboxed execution environment. The final hardened test run is 33 passed. Both physical-Mac qualifying smokes and the selected-candidate Wi-Fi-off proof remain operator-only and unrun.
