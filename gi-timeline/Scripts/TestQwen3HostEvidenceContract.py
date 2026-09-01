#!/usr/bin/env python3
"""Fail-closed portability and integrity check for the committed host capture."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "QA" / "host-inference-evidence-20260828"
MANIFEST = EVIDENCE / "CAPTURE_MANIFEST.json"
RUNNER = ROOT / "Scripts" / "RunQwen3HostSemanticProxy.py"
EXPECTED_FIELDS = ["subject", "bristol", "mixed", "color", "red", "black", "glossy"]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_runner() -> object:
    spec = importlib.util.spec_from_file_location("qwen3_host_proxy", RUNNER)
    require(spec is not None and spec.loader is not None, "runner must be importable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    manifest = json.loads(MANIFEST.read_text())
    require(
        manifest["capture_source_commit"] == "ee53b115297a9f753808ef0eca6a53efdb7c4606",
        "capture source commit mismatch",
    )
    require(manifest["route"] == "host_python_mlx_semantic_proxy", "route mismatch")
    require(manifest["qualification"].startswith("NOT_DEVICE_QUALIFIED"), "qualification missing")
    require(
        all(not Path(item["path"]).is_absolute() for item in manifest["artifacts"]),
        "manifest artifacts must be repository-relative",
    )
    for artifact in manifest["artifacts"]:
        path = EVIDENCE / artifact["path"]
        require(path.is_file(), f"missing artifact: {artifact['path']}")
        require(sha256(path) == artifact["sha256"], f"hash mismatch: {artifact['path']}")

    raw = json.loads((EVIDENCE / "formed-brown/raw-per-field.json").read_text())
    fused = json.loads((EVIDENCE / "formed-brown/fused-evidence.json").read_text())
    attempt = json.loads((EVIDENCE / "attempt-01-plain-prompt-failed/preparation.json").read_text())
    identities = manifest["identities"]
    require(raw["model_id"] == identities["model_id"], "model identity mismatch")
    require(raw["model_revision"] == identities["model_revision"], "model revision mismatch")
    require(
        raw["snapshot_model_safetensors_sha256"] == identities["snapshot_model_safetensors_sha256"],
        "snapshot hash mismatch",
    )
    require(raw["fixture_sha256"] == identities["fixture_sha256"], "fixture hash mismatch")
    require(
        raw["preprocessing"]["derivative"]["derivativeRGBASHA256"]
        == identities["prepared_derivative_rgba_sha256"],
        "prepared derivative hash mismatch",
    )
    require(fused["promptSetSHA256"] == identities["prompt_set_sha256"], "prompt set hash mismatch")
    require([item["field"] for item in raw["fields"]] == EXPECTED_FIELDS, "field order mismatch")
    require(all(item["raw_utf8_sha256"] for item in raw["fields"]), "missing raw output hash")
    require(all(not item["qualified"] for item in fused["runEvidence"]["fields"]), "proxy labels admitted")

    formed_png = raw["preprocessing"]["derivativePNGPath"]
    require(attempt["derivativePNGPath"] == formed_png, "known attempt-01 path mismatch changed")
    require("later formed-brown" in manifest["historical_note"]["attempt_01_preparation_derivative_png_path"], "mismatch note missing")

    runner = load_runner()
    require(runner.repository_root() == ROOT, "runner root must derive from __file__")
    source = RUNNER.read_text()
    require(source.count("cwd=repo_root") == 2, "both SwiftPM commands must be repository-root anchored")
    with tempfile.TemporaryDirectory() as temporary:
        result = subprocess.run(
            [sys.executable, str(RUNNER), "--help"], cwd=temporary, text=True, capture_output=True
        )
    require(result.returncode == 0 and "--model-root" in result.stdout, "runner is not cwd-independent")
    print("Qwen3 host evidence contract PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
