"""Create a selectable offline-proof candidate from canonical, live-bound smoke evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

IMPORT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_ROOT))
sys.path.insert(0, str(IMPORT_ROOT / "scripts"))

from schemas import AnalysisResponse
from server_process import read_identity, validate_command
from smoke_test_model import ADAPTERS, allowed_template, assertion_transcript_hash, contract_hashes, safe_output_path, structured_signature


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_workspace_file(root: Path, relative: object, label: str) -> Path:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError(f"{label} must be a nonempty workspace-relative path")
    path = safe_output_path(root, root / relative, label)
    if not path.is_file():
        raise ValueError(f"{label} is missing or unsafe")
    return path


def positive_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise ValueError(f"{label} must be a positive finite number")
    return float(value)


def validate_recorded_live_proof(root: Path, snapshot: Path, pid: int, proof: object) -> dict:
    required = {"pid", "process_command", "executable_path", "start_time", "socket_proof"}
    if not isinstance(proof, dict) or set(proof) != required or proof.get("pid") != pid:
        raise ValueError("smoke evidence lacks an exact PID identity/socket proof")
    validate_command(root, snapshot, 8080, proof["process_command"])
    expected_executables = {
        str((root / ".venv/bin/python").resolve()),
        str((root / ".venv/bin/python3").resolve()),
        str((root / ".venv/bin/python3.12").resolve()),
    }
    if proof["executable_path"] not in expected_executables:
        raise ValueError("recorded server executable is not the resolved workspace Python")
    if not isinstance(proof["start_time"], str) or not proof["start_time"].strip():
        raise ValueError("recorded server start time is missing")
    if proof["socket_proof"] != "127.0.0.1:8080 (LISTEN)":
        raise ValueError("recorded server socket proof is not exact loopback port 8080")
    return proof


def validate_passed_evidence(root: Path, evidence: dict) -> dict:
    """Recompute every assertion that permits full-smoke evidence to unlock a candidate."""
    root = root.resolve()
    if evidence.get("status") != "passed" or evidence.get("mode") is not None:
        raise ValueError("candidate requires passed full-smoke evidence")

    binding = evidence.get("model_binding")
    required_binding = {"key", "model_id", "revision", "snapshot_path", "pid", "port"}
    if not isinstance(binding, dict) or set(binding) != required_binding:
        raise ValueError("smoke evidence lacks a complete model binding")
    if isinstance(binding["pid"], bool) or not isinstance(binding["pid"], int) or binding["pid"] <= 1 or binding["port"] != 8080:
        raise ValueError("smoke evidence lacks a qualifying PID/port binding")
    models = json.loads((root / "model_manifest.json").read_text())["models"]
    if binding["key"] not in models:
        raise ValueError("smoke evidence names an unknown model key")
    pinned = models[binding["key"]]
    if any(binding[key] != pinned[key] for key in ("model_id", "revision", "snapshot_path")):
        raise ValueError("smoke evidence does not match the pinned model manifest")
    snapshot = (root / binding["snapshot_path"]).resolve()
    if root not in snapshot.parents or not snapshot.is_dir():
        raise ValueError("smoke evidence snapshot is missing or unsafe")
    before_proof = validate_recorded_live_proof(root, snapshot, binding["pid"], evidence.get("live_proof_before"))
    after_proof = validate_recorded_live_proof(root, snapshot, binding["pid"], evidence.get("live_proof_after"))
    if before_proof != after_proof:
        raise ValueError("server identity/socket proof changed during smoke")

    adapter = evidence.get("winning_adapter")
    template = evidence.get("request_template")
    if adapter not in ADAPTERS or not isinstance(template, dict) or template.get("adapter") != adapter or not allowed_template(template):
        raise ValueError("smoke evidence lacks its earned adapter/request template")
    working_request = evidence.get("working_request")
    expected_request = ADAPTERS[adapter](root / "data/demo/synthetic_brown_clay_prop.png", template)
    if working_request != expected_request:
        raise ValueError("smoke evidence working request does not match the current frozen contract")
    expected_hashes = contract_hashes(root, template, expected_request, binding)
    if evidence.get("contract_hashes") != expected_hashes:
        raise ValueError("smoke evidence contract hashes are absent or stale")

    adapter_attempts = evidence.get("adapter_attempts")
    if not isinstance(adapter_attempts, list) or not adapter_attempts:
        raise ValueError("smoke evidence lacks adapter-discovery attempts")
    accepted = []
    for attempt in adapter_attempts:
        if not isinstance(attempt, dict) or attempt.get("status") not in {"accepted", "rejected"}:
            raise ValueError("adapter-discovery evidence is incomplete")
        candidate_template = attempt.get("request_template")
        if attempt.get("adapter") not in ADAPTERS or not isinstance(candidate_template, dict):
            raise ValueError("adapter-discovery evidence contains an unsupported request")
        if candidate_template.get("adapter") != attempt["adapter"] or not allowed_template(candidate_template):
            raise ValueError("adapter-discovery evidence contains a malformed request template")
        if attempt["status"] == "accepted":
            positive_number(attempt.get("seconds"), "accepted adapter latency")
            accepted.append(attempt)
        elif not isinstance(attempt.get("error"), str) or not attempt["error"].strip():
            raise ValueError("rejected adapter evidence must record its error")
    if len(accepted) != 1 or accepted[0]["request_template"] != template or adapter_attempts[-1] != accepted[0]:
        raise ValueError("winning adapter/template was not uniquely earned by discovery")

    fixture_attempts = evidence.get("fixture_attempts")
    if not isinstance(fixture_attempts, list) or not 1 <= len(fixture_attempts) <= 3:
        raise ValueError("smoke evidence must contain one to three fixture attempts")
    parsed_attempts = []
    expected_labels = ["brown_first", "brown_second", "green"]
    for index, record in enumerate(fixture_attempts):
        if not isinstance(record, dict) or record.get("attempt") != index:
            raise ValueError("fixture attempts must be consecutive and zero-based")
        fixtures = record.get("fixtures")
        if not isinstance(fixtures, dict) or set(fixtures) != {"brown", "green"}:
            raise ValueError("fixture attempt lacks its exact brown/green bindings")
        expected_prefix = "data/demo" if index == 0 else f".devdata_preflight/fixture_attempts/{index}"
        for color in ("brown", "green"):
            entry = fixtures[color]
            if not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
                raise ValueError("fixture binding must contain only path and SHA-256")
            expected_path = f"{expected_prefix}/synthetic_{color}_clay_prop.png"
            if entry["path"] != expected_path:
                raise ValueError("fixture attempt path does not match the staged retry contract")
            fixture_path = safe_workspace_file(root, entry["path"], "fixture")
            if entry["sha256"] != sha256_file(fixture_path):
                raise ValueError("fixture SHA-256 does not match its recorded file")

        results = record.get("results")
        if not isinstance(results, list) or [item.get("fixture") if isinstance(item, dict) else None for item in results] != expected_labels:
            raise ValueError("fixture attempt must record brown twice and green once in order")
        parsed_results = []
        for result in results:
            if set(result) != {"fixture", "seconds", "response"}:
                raise ValueError("fixture result contains missing or unexpected fields")
            positive_number(result["seconds"], "fixture request latency")
            parsed_results.append(AnalysisResponse.model_validate(result["response"]).model_dump(mode="json"))
        brown_one, brown_two, green = parsed_results
        both_absent = (
            not brown_one["image_assessment"]["contains_relevant_subject"]
            and not green["image_assessment"]["contains_relevant_subject"]
        )
        if record.get("both_props_reported_absent") is not both_absent:
            raise ValueError("fixture retry decision does not match the validated responses")
        if index < len(fixture_attempts) - 1:
            if not both_absent or record.get("next_action") != f"generate non-destructive synthetic retry variant {index + 1}":
                raise ValueError("fixture retry was not justified and recorded exactly")
        elif record.get("next_action") is not None:
            raise ValueError("final fixture attempt must not claim another retry")
        parsed_attempts.append((record, brown_one, brown_two, green))

    final_record, brown_one, brown_two, green = parsed_attempts[-1]
    if final_record["both_props_reported_absent"]:
        raise ValueError("both props remained unrecognized")
    if brown_one["image_assessment"]["contains_relevant_subject"] is not True:
        raise ValueError("brown fixture was not recognized as relevant")
    if green["image_assessment"]["contains_relevant_subject"] is not True:
        raise ValueError("green fixture was not recognized as relevant")
    if brown_one["visible_observations"]["primary_color"] not in {"brown", "light_brown", "dark_brown"}:
        raise ValueError("brown fixture did not produce a brown-family observation")
    if green["visible_observations"]["primary_color"] != "green":
        raise ValueError("green fixture did not produce a green observation")
    exact = brown_one == brown_two
    structured = structured_signature(brown_one) == structured_signature(brown_two)
    expected_determinism = "exact_json" if exact else "structured_enums_identical" if structured else None
    if expected_determinism is None or evidence.get("determinism") != expected_determinism:
        raise ValueError("determinism claim does not match the duplicate response evidence")
    warm_seconds = positive_number(evidence.get("warm_seconds"), "warm request latency")
    if warm_seconds != positive_number(final_record["results"][1]["seconds"], "second brown request latency"):
        raise ValueError("warm latency does not match the second brown request")
    if evidence.get("assertion_transcript_sha256") != assertion_transcript_hash(evidence):
        raise ValueError("smoke assertion transcript is absent, edited, or rebound")
    return evidence


def build_candidate(
    root: Path,
    evidence: dict,
    current_identity: dict,
    socket_proof: str,
    evidence_path: str,
    evidence_sha256: str,
) -> dict:
    validate_passed_evidence(root, evidence)
    binding = evidence["model_binding"]
    snapshot = (root / binding["snapshot_path"]).resolve()
    current_proof = {**current_identity, "socket_proof": socket_proof.strip()}
    validate_recorded_live_proof(root, snapshot, binding["pid"], current_proof)
    if current_proof != evidence["live_proof_after"]:
        raise ValueError("candidate PID identity differs from the process that completed smoke")
    return {
        "eligibility": "eligible_smoke",
        "model_key": binding["key"],
        "model_id": binding["model_id"],
        "revision": binding["revision"],
        "snapshot_path": binding["snapshot_path"],
        "pid": binding["pid"],
        "port": 8080,
        "socket_proof": socket_proof.strip(),
        "winning_adapter": evidence["winning_adapter"],
        "request_template": evidence["request_template"],
        "determinism": evidence["determinism"],
        "warm_seconds": evidence["warm_seconds"],
        "contract_hashes": evidence["contract_hashes"],
        "assertion_transcript_sha256": evidence["assertion_transcript_sha256"],
        "process_identity": current_identity,
        "smoke_evidence": evidence_path,
        "smoke_evidence_sha256": evidence_sha256,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    raw_evidence_path = Path(args.evidence)
    if not raw_evidence_path.is_absolute():
        raw_evidence_path = Path.cwd() / raw_evidence_path
    try:
        evidence_path = safe_output_path(root, raw_evidence_path, "smoke evidence")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if not evidence_path.is_file():
        raise SystemExit("smoke evidence must be an existing file inside the workspace")
    try:
        evidence_bytes = evidence_path.read_bytes()
        evidence = json.loads(evidence_bytes)
        validate_passed_evidence(root, evidence)
        binding = evidence.get("model_binding", {})
        snapshot = (root / binding["snapshot_path"]).resolve()
        identity = read_identity(root, snapshot, 8080, binding.get("pid"))
        proof = subprocess.run(
            [str(root / "scripts/verify_socket.sh"), str(binding["pid"]), "8080"],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
        ).stdout.strip()
        relative_evidence = evidence_path.relative_to(root).as_posix()
        candidate = build_candidate(
            root,
            evidence,
            identity,
            proof,
            relative_evidence,
            hashlib.sha256(evidence_bytes).hexdigest(),
        )
    except (OSError, TypeError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error

    try:
        candidate_dir = safe_output_path(root, root / ".devdata_preflight/candidates", "candidate directory")
        raw_output = Path(args.output) if args.output else candidate_dir / f"{candidate['model_key']}.json"
        if not raw_output.is_absolute():
            raw_output = Path.cwd() / raw_output
        output = safe_output_path(root, raw_output, "candidate output")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if candidate_dir != output.parent or output.suffix != ".json":
        raise SystemExit("candidate output must be a JSON file directly under .devdata_preflight/candidates")
    candidate_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if output.exists():
        raise SystemExit(f"refusing to overwrite existing candidate: {output}")
    try:
        pending = safe_output_path(root, output.with_suffix(".json.pending"), "pending candidate")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if pending.exists():
        raise SystemExit(f"refusing to overwrite pending candidate: {pending}")
    try:
        with pending.open("x") as handle:
            handle.write(json.dumps(candidate, indent=2) + "\n")
        pending.chmod(0o600)
        subprocess.run(
            [sys.executable, "-I", str(root / "scripts/primary_manifest.py"), "--manifest", str(pending)],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        pending.replace(output)
    except (OSError, subprocess.SubprocessError) as error:
        if pending.exists():
            pending.unlink()
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        raise SystemExit(detail) from error
    print(output.relative_to(root).as_posix())


if __name__ == "__main__":
    main()
