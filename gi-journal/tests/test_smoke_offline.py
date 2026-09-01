import copy
import importlib.util
import hashlib
import json
import sys
import tempfile
from pathlib import Path

import pytest


def load_smoke_module():
    if "smoke_test_model" in sys.modules:
        return sys.modules["smoke_test_model"]
    path = Path(__file__).resolve().parents[1] / "scripts" / "smoke_test_model.py"
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("smoke_test_model", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["smoke_test_model"] = module
    spec.loader.exec_module(module)
    return module


def valid_response(color: str = "brown") -> dict:
    return {
        "schema_version": "1.0",
        "image_assessment": {"contains_relevant_subject": True, "quality": "good", "quality_issues": [], "quality_explanation": ""},
        "visible_observations": {
            "apparent_bristol_type": 4, "bristol_certainty": "medium", "primary_color": color,
            "secondary_colors": [], "form_descriptors": ["smooth_formed"],
            "red_appearing_material": "not_observed", "black_tarry_appearance": "not_observed",
            "mucus_appearing_material": "not_observed", "other_visible_features": [],
        },
        "neutral_description": f"A smooth, formed, {color} staged subject is visible.",
        "uncertainties": [], "retake_guidance": [],
    }


class FakeResponse:
    def raise_for_status(self):
        return None

    def json(self):
        return {"choices": [{"message": {"content": json.dumps(valid_response())}}]}


def load_script_module(name: str):
    path = Path(__file__).resolve().parents[1] / "scripts" / f"{name}.py"
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def canonical_passed_evidence(root: Path, model_key: str = "e4b", pid: int = 123) -> dict:
    smoke = load_smoke_module()
    pinned = json.loads((root / "model_manifest.json").read_text())["models"][model_key]
    template = smoke.request_template("openai_base64_image_url", False)
    brown_path = root / "data/demo/synthetic_brown_clay_prop.png"
    green_path = root / "data/demo/synthetic_green_clay_prop.png"
    working_request = smoke.ADAPTERS[template["adapter"]](brown_path, template)
    brown = valid_response("brown")
    green = valid_response("green")
    binding = {"key": model_key, **pinned, "pid": pid, "port": 8080}
    snapshot = (root / pinned["snapshot_path"]).resolve()
    identity = {
        "pid": pid,
        "process_command": f"{root}/.venv/bin/python {root}/.venv/bin/mlx_vlm.server --model {snapshot} --host 127.0.0.1 --port 8080",
        "executable_path": str((root / ".venv/bin/python").resolve()),
        "start_time": "Fri Jul 31 10:00:00 2026",
    }
    live_proof = {**identity, "socket_proof": "127.0.0.1:8080 (LISTEN)"}
    evidence = {
        "status": "passed",
        "model_binding": binding,
        "live_proof_before": live_proof,
        "live_proof_after": copy.deepcopy(live_proof),
        "adapter_attempts": [{
            "adapter": template["adapter"], "request_template": template,
            "status": "accepted", "seconds": 0.75,
        }],
        "fixture_attempts": [{
            "attempt": 0,
            "fixtures": {
                "brown": {"path": "data/demo/synthetic_brown_clay_prop.png", "sha256": hashlib.sha256(brown_path.read_bytes()).hexdigest()},
                "green": {"path": "data/demo/synthetic_green_clay_prop.png", "sha256": hashlib.sha256(green_path.read_bytes()).hexdigest()},
            },
            "results": [
                {"fixture": "brown_first", "seconds": 1.25, "response": brown},
                {"fixture": "brown_second", "seconds": 0.5, "response": copy.deepcopy(brown)},
                {"fixture": "green", "seconds": 0.6, "response": green},
            ],
            "both_props_reported_absent": False,
        }],
        "winning_adapter": template["adapter"],
        "request_template": template,
        "working_request": working_request,
        "contract_hashes": smoke.contract_hashes(
            root,
            template,
            working_request,
            binding,
        ),
        "determinism": "exact_json",
        "warm_seconds": 0.5,
    }
    evidence["assertion_transcript_sha256"] = smoke.assertion_transcript_hash(evidence)
    return evidence


def recorded_identity(evidence: dict) -> dict:
    return {
        key: evidence["live_proof_after"][key]
        for key in ("pid", "process_command", "executable_path", "start_time")
    }


class FakeClient:
    def __init__(self):
        self.calls = []

    def post(self, url, json):
        self.calls.append((url, json))
        return FakeResponse()


def test_offline_one_request_uses_only_earned_adapter_once():
    smoke = load_smoke_module()
    client = FakeClient()
    fixture = Path(__file__).resolve().parents[1] / "data" / "demo" / "synthetic_brown_clay_prop.png"
    template = smoke.request_template("openai_base64_image_url", True)
    response, _ = smoke.perform_one_request(client, "http://127.0.0.1:8080", template, fixture)
    assert response["visible_observations"]["primary_color"] == "brown"
    assert len(client.calls) == 1
    url, request = client.calls[0]
    assert url == "http://127.0.0.1:8080/v1/chat/completions"
    assert request["seed"] == 0
    assert request["temperature"] == 0


def test_request_template_records_seeded_and_seedless_variants():
    smoke = load_smoke_module()
    assert smoke.request_template("mlx_vlm_input_image", True) == {
        "adapter": "mlx_vlm_input_image", "endpoint": "/v1/chat/completions",
        "temperature": 0, "seed": 0, "response_format": "json_schema",
    }
    assert smoke.request_template("mlx_vlm_input_image", False) == {
        "adapter": "mlx_vlm_input_image", "endpoint": "/v1/chat/completions",
        "temperature": 0, "response_format": "json_schema",
    }
    try:
        smoke.request_template("unknown", True)
    except ValueError:
        pass
    else:
        raise AssertionError("unknown adapter must be rejected")


def test_production_schema_is_fully_inlined():
    smoke = load_smoke_module()
    rendered = json.dumps(smoke.schema())
    assert '"$ref"' not in rendered
    assert '"$defs"' not in rendered


def test_remote_url_is_rejected_before_image_read_or_post():
    smoke = load_smoke_module()
    client = FakeClient()
    try:
        smoke.perform_one_request(client, "https://example.com:8080", smoke.request_template("openai_base64_image_url", True), Path("does-not-exist.png"))
    except ValueError as error:
        assert "loopback" in str(error) or "HTTP" in str(error)
    else:
        raise AssertionError("remote URL must be rejected")
    assert client.calls == []
    try:
        smoke.perform_one_request(client, "http://localhost:8080", smoke.request_template("openai_base64_image_url", True), Path("does-not-exist.png"))
    except ValueError as error:
        assert "127.0.0.1" in str(error)
    else:
        raise AssertionError("qualifying requests must use literal 127.0.0.1")
    assert client.calls == []


def test_retry_variants_are_non_destructive_and_labeled(tmp_path):
    smoke = load_smoke_module()
    root = Path(__file__).resolve().parents[1]
    originals = [root / "data/demo/synthetic_brown_clay_prop.png", root / "data/demo/synthetic_green_clay_prop.png"]
    before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in originals]
    first = smoke.make_pair(tmp_path / "attempt-1", variant=1)
    second = smoke.make_pair(tmp_path / "attempt-2", variant=2)
    assert all(path.is_file() for path in (*first, *second))
    assert [hashlib.sha256(path.read_bytes()).hexdigest() for path in originals] == before
    assert hashlib.sha256(first[0].read_bytes()).hexdigest() != hashlib.sha256(second[0].read_bytes()).hexdigest()


def test_candidate_binds_exact_process_socket_model_and_template():
    root = Path(__file__).resolve().parents[1]
    module = load_script_module("create_eligible_candidate")
    evidence = canonical_passed_evidence(root)
    candidate = module.build_candidate(
        root, evidence, recorded_identity(evidence), "127.0.0.1:8080 (LISTEN)",
        "smoke_evidence_e4b.json", "0" * 64,
    )
    assert candidate["port"] == 8080
    assert "seed" not in candidate["request_template"]
    assert candidate["determinism"] == "exact_json"
    assert candidate["contract_hashes"] == evidence["contract_hashes"]


def test_minimal_or_stale_smoke_evidence_cannot_unlock_candidate():
    root = Path(__file__).resolve().parents[1]
    candidate_module = load_script_module("create_eligible_candidate")
    minimal = {
        "status": "passed",
        "model_binding": {"key": "e4b", **json.loads((root / "model_manifest.json").read_text())["models"]["e4b"], "pid": 123, "port": 8080},
        "winning_adapter": "openai_base64_image_url",
        "request_template": load_smoke_module().request_template("openai_base64_image_url", False),
    }
    with pytest.raises(ValueError):
        candidate_module.validate_passed_evidence(root, minimal)
    stale = canonical_passed_evidence(root)
    stale["contract_hashes"]["schema_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="hashes"):
        candidate_module.validate_passed_evidence(root, stale)


def test_smoke_transcript_cannot_be_rebound_to_the_other_model():
    root = Path(__file__).resolve().parents[1]
    candidate_module = load_script_module("create_eligible_candidate")
    rebound = canonical_passed_evidence(root, "e4b", 123)
    e2b = json.loads((root / "model_manifest.json").read_text())["models"]["e2b"]
    rebound["model_binding"] = {"key": "e2b", **e2b, "pid": 456, "port": 8080}
    with pytest.raises(ValueError, match="identity|hashes|transcript"):
        candidate_module.validate_passed_evidence(root, rebound)


def test_exact_process_parser_rejects_substring_bypasses():
    root = Path(__file__).resolve().parents[1]
    server_process = load_script_module("server_process")
    snapshot = (root / json.loads((root / "model_manifest.json").read_text())["models"]["e4b"]["snapshot_path"]).resolve()
    server = root / ".venv/bin/mlx_vlm.server"
    python = root / ".venv/bin/python"
    valid = f"{python} {server} --model {snapshot} --host 127.0.0.1 --port 8080"
    server_process.validate_command(root, snapshot, 8080, valid)
    invalid = [
        f"/tmp/wrong-python {server} --model {snapshot} --host 127.0.0.1 --port 8080",
        f"{python} /tmp/wrong-{server.name} --note {server} --model {snapshot} --host 127.0.0.1 --port 8080",
        f"{python} {server} --model {snapshot}-WRONG --host 127.0.0.1 --port 8080",
        f"{python} {server} --model {snapshot} --host 127.0.0.10 --port 8080",
        f"{python} {server} --model {snapshot} --host 127.0.0.1 --port 80800",
        f"{python} {server} --model {snapshot} --host 127.0.0.1 --port 8080 --extra value",
    ]
    for command in invalid:
        with pytest.raises(ValueError):
            server_process.validate_command(root, snapshot, 8080, command)


def test_primary_manifest_revalidates_evidence_hash_and_assertions():
    root = Path(__file__).resolve().parents[1]
    candidate_module = load_script_module("create_eligible_candidate")
    primary_module = load_script_module("primary_manifest")
    evidence = canonical_passed_evidence(root)
    scratch_root = root / ".devdata_preflight"
    scratch_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="manifest-test-", dir=scratch_root) as directory:
        directory_path = Path(directory)
        evidence_path = directory_path / "smoke.json"
        evidence_bytes = (json.dumps(evidence, indent=2) + "\n").encode()
        evidence_path.write_bytes(evidence_bytes)
        candidate = candidate_module.build_candidate(
            root, evidence, recorded_identity(evidence), "127.0.0.1:8080 (LISTEN)",
            evidence_path.relative_to(root).as_posix(), hashlib.sha256(evidence_bytes).hexdigest(),
        )
        manifest_path = directory_path / "candidate.json"
        manifest_path.write_text(json.dumps(candidate))
        assert primary_module.validate(root, manifest_path)[0] == "e4b"

        evidence_path.write_text(json.dumps({"status": "passed"}))
        with pytest.raises(ValueError, match="SHA-256"):
            primary_module.validate(root, manifest_path)
        forged_bytes = (json.dumps({**evidence, "warm_seconds": 99.0}) + "\n").encode()
        evidence_path.write_bytes(forged_bytes)
        candidate["smoke_evidence_sha256"] = hashlib.sha256(forged_bytes).hexdigest()
        manifest_path.write_text(json.dumps(candidate))
        with pytest.raises(ValueError, match="warm latency"):
            primary_module.validate(root, manifest_path)
