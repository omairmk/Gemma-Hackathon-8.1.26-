"""Validate a smoke-eligible primary manifest before any offline network action."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

IMPORT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_ROOT))
sys.path.insert(0, str(IMPORT_ROOT / "scripts"))


def validate(root: Path, manifest_path: Path) -> tuple[str, Path]:
    root = root.resolve()
    manifest_path = manifest_path.resolve()
    if root not in manifest_path.parents or not manifest_path.is_file():
        raise ValueError("primary runtime manifest must be an existing workspace file")
    data = json.loads(manifest_path.read_text())
    required = {
        "eligibility", "model_key", "model_id", "revision", "snapshot_path", "pid", "port",
        "socket_proof", "winning_adapter", "request_template", "determinism", "warm_seconds",
        "contract_hashes", "assertion_transcript_sha256", "process_identity", "smoke_evidence", "smoke_evidence_sha256",
    }
    if not required <= data.keys() or data["eligibility"] != "eligible_smoke":
        raise ValueError("primary manifest is absent or unverified")
    if isinstance(data["pid"], bool) or not isinstance(data["pid"], int) or data["pid"] <= 1:
        raise ValueError("primary manifest lacks a qualifying PID")
    if data["port"] != 8080 or data["socket_proof"] != "127.0.0.1:8080 (LISTEN)":
        raise ValueError("primary manifest lacks exact PID-bound loopback proof")

    models = json.loads((root / "model_manifest.json").read_text())["models"]
    if data["model_key"] not in models:
        raise ValueError("primary manifest names an unknown model")
    model = models[data["model_key"]]
    if any(data[key] != model[key] for key in ("model_id", "revision", "snapshot_path")):
        raise ValueError("primary manifest does not match pinned model manifest")
    snapshot = (root / data["snapshot_path"]).resolve()
    if root not in snapshot.parents or not snapshot.is_dir():
        raise ValueError("primary snapshot is missing or unsafe")

    if not isinstance(data["smoke_evidence"], str) or Path(data["smoke_evidence"]).is_absolute():
        raise ValueError("primary manifest smoke evidence path is unsafe")
    evidence_path = (root / data["smoke_evidence"]).resolve()
    if root not in evidence_path.parents or not evidence_path.is_file():
        raise ValueError("primary manifest smoke evidence is missing or unsafe")
    evidence_bytes = evidence_path.read_bytes()
    if hashlib.sha256(evidence_bytes).hexdigest() != data["smoke_evidence_sha256"]:
        raise ValueError("primary manifest smoke evidence SHA-256 does not match")
    evidence = json.loads(evidence_bytes)
    from create_eligible_candidate import validate_passed_evidence

    validate_passed_evidence(root, evidence)
    binding = evidence["model_binding"]
    comparisons = {
        "model_key": binding["key"],
        "model_id": binding["model_id"],
        "revision": binding["revision"],
        "snapshot_path": binding["snapshot_path"],
        "pid": binding["pid"],
        "port": binding["port"],
        "winning_adapter": evidence["winning_adapter"],
        "request_template": evidence["request_template"],
        "determinism": evidence["determinism"],
        "warm_seconds": evidence["warm_seconds"],
        "contract_hashes": evidence["contract_hashes"],
        "assertion_transcript_sha256": evidence["assertion_transcript_sha256"],
        "process_identity": {key: evidence["live_proof_after"][key] for key in ("pid", "process_command", "executable_path", "start_time")},
    }
    if any(data[key] != value for key, value in comparisons.items()):
        raise ValueError("primary manifest fields do not match their validated smoke evidence")
    return data["model_key"], snapshot


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        key, snapshot = validate(root, Path(args.manifest))
    except (OSError, TypeError, ValueError, KeyError, json.JSONDecodeError) as error:
        raise SystemExit(str(error)) from error
    print(f"{key}|{snapshot}")


if __name__ == "__main__":
    main()
