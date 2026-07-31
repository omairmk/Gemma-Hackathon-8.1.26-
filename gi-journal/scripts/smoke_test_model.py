"""Live Prompt A smoke runner with incremental, model-bound evidence."""

from __future__ import annotations

import argparse
import base64
import functools
import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit

import httpx

IMPORT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMPORT_ROOT))
sys.path.insert(0, str(IMPORT_ROOT / "scripts"))

from make_fixtures import make_pair
from prompts import IMAGE_SYSTEM_PROMPT
from schemas import AnalysisResponse
from server_process import read_identity

QUALIFYING_PORT = 8080


def schema() -> dict:
    raw = AnalysisResponse.model_json_schema()
    definitions = raw.pop("$defs", {})

    def inline(value):
        if isinstance(value, list):
            return [inline(item) for item in value]
        if not isinstance(value, dict):
            return value
        if "$ref" in value:
            prefix = "#/$defs/"
            reference = value["$ref"]
            if not reference.startswith(prefix) or reference[len(prefix):] not in definitions:
                raise ValueError(f"unsupported schema reference: {reference}")
            merged = {**definitions[reference[len(prefix):]], **{key: item for key, item in value.items() if key != "$ref"}}
            return inline(merged)
        return {key: inline(item) for key, item in value.items()}

    return inline(raw)


def validate_base_url(value: str) -> str:
    """Reject non-loopback endpoints before any image is read or sent."""
    parsed = urlsplit(value)
    if parsed.scheme != "http" or parsed.username or parsed.password:
        raise ValueError("model base URL must be uncredentialed HTTP")
    if parsed.hostname != "127.0.0.1":
        raise ValueError("qualifying model base URL must use the literal IPv4 loopback address 127.0.0.1")
    if parsed.port != QUALIFYING_PORT or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise ValueError("qualifying model base URL must be loopback port 8080 with no path, query, or fragment")
    return f"http://127.0.0.1:{QUALIFYING_PORT}"


def model_binding(root: Path, key: str, pid: int) -> dict:
    spec = json.loads((root / "model_manifest.json").read_text())["models"][key]
    resolved = (root / spec["snapshot_path"]).resolve()
    if root not in resolved.parents or not resolved.is_dir():
        raise SystemExit("manifest snapshot path is missing or unsafe")
    return {"key": key, "model_id": spec["model_id"], "revision": spec["revision"], "snapshot_path": spec["snapshot_path"], "pid": pid, "port": QUALIFYING_PORT}


def request_template(adapter: str, seed_supported: bool) -> dict:
    if adapter not in ADAPTERS:
        raise ValueError(f"unsupported adapter: {adapter}")
    template = {
        "adapter": adapter,
        "endpoint": "/v1/chat/completions",
        "temperature": 0,
        "response_format": "json_schema",
    }
    if seed_supported:
        template["seed"] = 0
    return template


def sampling_fields(template: dict) -> dict:
    fields = {"temperature": template["temperature"]}
    if "seed" in template:
        fields["seed"] = template["seed"]
    return fields


def payload_base64(image: Path, template: dict) -> dict:
    encoded = base64.b64encode(image.read_bytes()).decode("ascii")
    return {"model": "local", **sampling_fields(template), "messages": [
        {"role": "system", "content": IMAGE_SYSTEM_PROMPT},
        {"role": "user", "content": [{"type": "text", "text": "Analyze this image."}, {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{encoded}"}}]},
    ], "response_format": {"type": "json_schema", "json_schema": {"name": "analysis_response", "schema": schema()}}}


def payload_input_image(image: Path, template: dict) -> dict:
    return {"model": "local", **sampling_fields(template), "messages": [
        {"role": "system", "content": IMAGE_SYSTEM_PROMPT},
        {"role": "user", "content": "Analyze this image."},
    ], "input_image": str(image), "response_format": {"type": "json_schema", "json_schema": {"name": "analysis_response", "schema": schema()}}}


def payload_local_url(image: Path, template: dict) -> dict:
    return {"model": "local", **sampling_fields(template), "messages": [
        {"role": "system", "content": IMAGE_SYSTEM_PROMPT},
        {"role": "user", "content": [{"type": "text", "text": "Analyze this image."}, {"type": "image_url", "image_url": {"url": str(image)}}]},
    ], "response_format": {"type": "json_schema", "json_schema": {"name": "analysis_response", "schema": schema()}}}


ADAPTERS: dict[str, Callable[[Path, dict], dict]] = {
    "openai_base64_image_url": payload_base64,
    "mlx_vlm_input_image": payload_input_image,
    "local_path_image_url": payload_local_url,
}


def allowed_template(template: dict) -> bool:
    adapter = template.get("adapter")
    return template in {False: request_template(adapter, False), True: request_template(adapter, True)}.values() if adapter in ADAPTERS else False


def load_eligible_primary(root: Path, manifest_path: Path, model_key: str) -> dict:
    from primary_manifest import validate

    validated_key, _ = validate(root, manifest_path)
    primary = json.loads(manifest_path.read_text())
    needed = {"eligibility", "model_key", "model_id", "revision", "snapshot_path", "pid", "port", "socket_proof", "winning_adapter", "request_template"}
    if not needed <= primary.keys() or primary["eligibility"] != "eligible_smoke" or primary["port"] != QUALIFYING_PORT:
        raise ValueError("primary manifest is absent or unverified")
    pinned = model_binding(root, model_key, primary["pid"])
    if validated_key != model_key or primary["model_key"] != model_key or any(primary[key] != pinned[key] for key in ("model_id", "revision", "snapshot_path", "port")):
        raise ValueError("primary manifest does not match this pinned model binding")
    if primary["winning_adapter"] != primary["request_template"].get("adapter") or not allowed_template(primary["request_template"]):
        raise ValueError("primary manifest lacks the exact earned request template")
    return primary


def extract_json(response: dict) -> dict:
    content = response["choices"][0]["message"]["content"]
    if isinstance(content, str):
        return json.loads(content.removeprefix("```json").removesuffix("```").strip())
    return content


def structured_signature(value: dict) -> dict:
    return {"image_assessment": value["image_assessment"], "visible_observations": value["visible_observations"]}


def perform_one_request(client: httpx.Client, base_url: str, template: dict, image: Path) -> tuple[dict, float]:
    base_url = validate_base_url(base_url)
    if not allowed_template(template):
        raise ValueError("request template is not an earned supported template")
    started = time.monotonic()
    response = client.post(f"{base_url}{template['endpoint']}", json=ADAPTERS[template["adapter"]](image, template))
    response.raise_for_status()
    value = AnalysisResponse.model_validate(extract_json(response.json())).model_dump(mode="json")
    return value, time.monotonic() - started


def write_evidence(path: Path, evidence: dict) -> None:
    path = safe_output_path(IMPORT_ROOT, path, "evidence path")
    encoded = (json.dumps(evidence, indent=2) + "\n").encode()
    temporary = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        temporary = Path(temporary_name)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        safe_output_path(IMPORT_ROOT, path, "evidence path")
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def canonical_hash(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def streamed_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


@functools.lru_cache(maxsize=4)
def cached_snapshot_content_hash(signature: str, serialized_records: str) -> str:
    """Hash model bytes once per unchanged metadata signature in this process."""
    del signature
    records = json.loads(serialized_records)
    for record in records:
        path = Path(record.pop("resolved_path"))
        before = path.stat()
        expected = (record["size"], record["mtime_ns"], record["ctime_ns"])
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != expected:
            raise ValueError("model snapshot changed before content hashing")
        record["sha256"] = streamed_sha256(path)
        after = path.stat()
        if (after.st_size, after.st_mtime_ns, after.st_ctime_ns) != expected:
            raise ValueError("model snapshot changed during content hashing")
    return canonical_hash(records)


def snapshot_fingerprint(root: Path, binding: dict) -> dict:
    """Content-bind every resolved snapshot file and reject escaping symlinks."""
    snapshot = (root / binding["snapshot_path"]).resolve()
    if root not in snapshot.parents or not snapshot.is_dir():
        raise ValueError("model snapshot is missing or unsafe")
    records = []
    for path in sorted(snapshot.rglob("*"), key=lambda item: item.relative_to(snapshot).as_posix()):
        if path.is_symlink():
            resolved = path.resolve()
            if root not in resolved.parents or not resolved.is_file():
                raise ValueError("model snapshot symlink escapes the workspace or is not a file")
        elif path.is_dir():
            continue
        elif path.is_file():
            resolved = path.resolve()
            if root not in resolved.parents:
                raise ValueError("model snapshot file escapes the workspace")
        else:
            raise ValueError("model snapshot contains an unsupported filesystem entry")
        stat = resolved.stat()
        records.append({
            "path": path.relative_to(snapshot).as_posix(),
            "resolved_path": str(resolved),
            "size": stat.st_size,
            "mtime_ns": stat.st_mtime_ns,
            "ctime_ns": stat.st_ctime_ns,
        })
    if not records:
        raise ValueError("model snapshot contains no files")
    serialized = json.dumps(records, sort_keys=True, separators=(",", ":"))
    metadata_signature = hashlib.sha256(serialized.encode()).hexdigest()
    return {
        "file_count": len(records),
        "total_bytes": sum(record["size"] for record in records),
        "metadata_sha256": metadata_signature,
        "content_manifest_sha256": cached_snapshot_content_hash(metadata_signature, serialized),
    }


def contract_hashes(root: Path, template: dict, working_request: dict, binding: dict) -> dict:
    brown = root / "data/demo/synthetic_brown_clay_prop.png"
    green = root / "data/demo/synthetic_green_clay_prop.png"
    return {
        "prompt_sha256": hashlib.sha256(IMAGE_SYSTEM_PROMPT.encode()).hexdigest(),
        "schema_sha256": canonical_hash(schema()),
        "model_binding_sha256": canonical_hash(binding),
        "model_manifest_sha256": hashlib.sha256((root / "model_manifest.json").read_bytes()).hexdigest(),
        "model_snapshot": snapshot_fingerprint(root, binding),
        "request_template_sha256": canonical_hash(template),
        "working_request_sha256": canonical_hash(working_request),
        "brown_fixture_sha256": hashlib.sha256(brown.read_bytes()).hexdigest(),
        "green_fixture_sha256": hashlib.sha256(green.read_bytes()).hexdigest(),
        "smoke_runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }


def assertion_transcript_hash(evidence: dict) -> str:
    """Bind the earned result transcript to its exact model/run before selection."""
    keys = (
        "model_binding", "live_proof_before", "live_proof_after", "adapter_attempts", "fixture_attempts", "winning_adapter",
        "request_template", "working_request", "contract_hashes", "determinism", "warm_seconds",
    )
    if any(key not in evidence for key in keys):
        raise ValueError("passed evidence lacks a complete assertion transcript")
    return canonical_hash({key: evidence[key] for key in keys})


def live_process_proof(root: Path, binding: dict) -> dict:
    snapshot = (root / binding["snapshot_path"]).resolve()
    identity = read_identity(root, snapshot, QUALIFYING_PORT, binding["pid"])
    socket_proof = subprocess.run(
        [str(root / "scripts/verify_socket.sh"), str(binding["pid"]), str(QUALIFYING_PORT)],
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
    ).stdout.strip()
    if socket_proof != f"127.0.0.1:{QUALIFYING_PORT} (LISTEN)":
        raise ValueError("live PID lacks the exact qualifying loopback socket")
    return {**identity, "socket_proof": socket_proof}


def fixture_record(root: Path, brown: Path, green: Path, attempt: int) -> dict:
    return {
        "attempt": attempt,
        "fixtures": {
            "brown": {"path": brown.resolve().relative_to(root).as_posix(), "sha256": hashlib.sha256(brown.read_bytes()).hexdigest()},
            "green": {"path": green.resolve().relative_to(root).as_posix(), "sha256": hashlib.sha256(green.read_bytes()).hexdigest()},
        },
        "results": [],
    }


def safe_output_path(root: Path, path: Path, label: str) -> Path:
    """Keep runtime writes under the workspace without traversing symlink components."""
    root = root.resolve()
    lexical = path if path.is_absolute() else root / path
    lexical = Path(str(lexical))
    try:
        relative = lexical.relative_to(root)
    except ValueError as error:
        raise ValueError(f"{label} must stay inside the workspace") from error
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"{label} must not traverse or replace a symlink")
    if root not in lexical.parent.resolve().parents and lexical.parent.resolve() != root:
        raise ValueError(f"{label} parent is unsafe")
    return lexical


def run_full_smoke(client: httpx.Client, base_url: str, root: Path, binding: dict, evidence_path: Path, before_proof: dict) -> dict:
    originals = (root / "data/demo/synthetic_brown_clay_prop.png", root / "data/demo/synthetic_green_clay_prop.png")
    evidence = {
        "status": "in_progress",
        "model_binding": binding,
        "live_proof_before": before_proof,
        "adapter_attempts": [],
        "fixture_attempts": [],
    }
    write_evidence(evidence_path, evidence)
    selected_template = None
    for adapter in ADAPTERS:
        for seed_supported in (True, False):
            template = request_template(adapter, seed_supported)
            attempt = {"adapter": adapter, "request_template": template, "status": "trying"}
            evidence["adapter_attempts"].append(attempt)
            write_evidence(evidence_path, evidence)
            try:
                _, seconds = perform_one_request(client, base_url, template, originals[0])
            except Exception as error:
                attempt.update(status="rejected", error=f"{type(error).__name__}: {error}")
                write_evidence(evidence_path, evidence)
                continue
            attempt.update(status="accepted", seconds=round(seconds, 3))
            selected_template = template
            write_evidence(evidence_path, evidence)
            break
        if selected_template:
            break
    if selected_template is None:
        evidence.update(status="failed", failure="No supported image request shape succeeded with or without seed=0.")
        write_evidence(evidence_path, evidence)
        raise AssertionError(evidence["failure"])
    working_request = ADAPTERS[selected_template["adapter"]](originals[0], selected_template)
    evidence.update(
        winning_adapter=selected_template["adapter"],
        request_template=selected_template,
        working_request=working_request,
        contract_hashes=contract_hashes(root, selected_template, working_request, binding),
    )
    write_evidence(evidence_path, evidence)

    final = None
    for fixture_attempt in range(3):
        if fixture_attempt == 0:
            brown, green = originals
        else:
            target = safe_output_path(root, root / ".devdata_preflight" / "fixture_attempts" / str(fixture_attempt), "retry fixture directory")
            safe_output_path(root, target / "synthetic_brown_clay_prop.png", "retry brown fixture")
            safe_output_path(root, target / "synthetic_green_clay_prop.png", "retry green fixture")
            brown, green = make_pair(target, variant=fixture_attempt)
        record = fixture_record(root, brown, green, fixture_attempt)
        evidence["fixture_attempts"].append(record)
        write_evidence(evidence_path, evidence)
        for label, image in (("brown_first", brown), ("brown_second", brown), ("green", green)):
            try:
                response, seconds = perform_one_request(client, base_url, selected_template, image)
            except Exception as error:
                evidence.update(status="failed", failure=f"fixture attempt {fixture_attempt} {label}: {type(error).__name__}: {error}")
                write_evidence(evidence_path, evidence)
                raise
            record["results"].append({"fixture": label, "seconds": round(seconds, 3), "response": response})
            write_evidence(evidence_path, evidence)
        brown_one, brown_two, green_result = record["results"]
        both_absent = not brown_one["response"]["image_assessment"]["contains_relevant_subject"] and not green_result["response"]["image_assessment"]["contains_relevant_subject"]
        record["both_props_reported_absent"] = both_absent
        write_evidence(evidence_path, evidence)
        final = record
        if not both_absent:
            break
        if fixture_attempt < 2:
            record["next_action"] = f"generate non-destructive synthetic retry variant {fixture_attempt + 1}"
            write_evidence(evidence_path, evidence)

    try:
        brown_one, brown_two, green_result = final["results"]
        exact = brown_one["response"] == brown_two["response"]
        structured = structured_signature(brown_one["response"]) == structured_signature(brown_two["response"])
        assert exact or structured, "determinism assertion failed"
        assert not final["both_props_reported_absent"], "both props remained unrecognized after two non-destructive fixture retries"
        assert brown_one["response"]["image_assessment"]["contains_relevant_subject"] is True
        assert green_result["response"]["image_assessment"]["contains_relevant_subject"] is True
        assert brown_one["response"]["visible_observations"]["primary_color"] in {"brown", "light_brown", "dark_brown"}
        assert green_result["response"]["visible_observations"]["primary_color"] == "green"
    except Exception as error:
        evidence.update(status="failed", failure=f"{type(error).__name__}: {error}")
        write_evidence(evidence_path, evidence)
        raise
    try:
        after_proof = live_process_proof(root, binding)
        if after_proof != before_proof:
            raise ValueError("server process identity changed during the qualifying smoke")
    except Exception as error:
        evidence.update(status="failed", failure=f"post-smoke live binding: {type(error).__name__}: {error}")
        write_evidence(evidence_path, evidence)
        raise
    evidence.update(
        status="passed",
        live_proof_after=after_proof,
        determinism="exact_json" if exact else "structured_enums_identical",
        warm_seconds=brown_two["seconds"],
    )
    evidence["assertion_transcript_sha256"] = assertion_transcript_hash(evidence)
    write_evidence(evidence_path, evidence)
    return evidence


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--evidence", default="smoke_evidence.json")
    parser.add_argument("--model-key", required=True, choices=("e4b", "e2b"))
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--offline-one-request", action="store_true")
    parser.add_argument("--primary-manifest")
    args = parser.parse_args()
    try:
        base_url = validate_base_url(args.base_url)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    root = Path(__file__).resolve().parents[1]
    raw_evidence_path = root / args.evidence if not Path(args.evidence).is_absolute() else Path(args.evidence)
    try:
        evidence_path = safe_output_path(root, raw_evidence_path, "evidence path")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    binding = model_binding(root, args.model_key, args.pid)
    client = httpx.Client(trust_env=False, follow_redirects=False, timeout=httpx.Timeout(120.0, connect=10.0))
    if args.offline_one_request:
        if not args.primary_manifest:
            raise SystemExit("--offline-one-request requires --primary-manifest")
        primary = load_eligible_primary(root, Path(args.primary_manifest), args.model_key)
        before_proof = live_process_proof(root, binding)
        evidence = {"status": "in_progress", "mode": "offline_one_request", "model_binding": binding, "live_proof_before": before_proof, "primary_manifest": str(Path(args.primary_manifest).resolve().relative_to(root)), "winning_adapter": primary["winning_adapter"], "request_template": primary["request_template"]}
        write_evidence(evidence_path, evidence)
        try:
            response, seconds = perform_one_request(client, base_url, primary["request_template"], root / "data/demo/synthetic_brown_clay_prop.png")
            assert response["image_assessment"]["contains_relevant_subject"] is True
            assert response["visible_observations"]["primary_color"] in {"brown", "light_brown", "dark_brown"}
        except Exception as error:
            evidence.update(status="failed", failure=f"{type(error).__name__}: {error}")
            write_evidence(evidence_path, evidence)
            raise
        try:
            after_proof = live_process_proof(root, binding)
            if after_proof != before_proof:
                raise ValueError("server process identity changed during the offline request")
        except Exception as error:
            evidence.update(status="failed", failure=f"post-request live binding: {type(error).__name__}: {error}")
            write_evidence(evidence_path, evidence)
            raise
        evidence.update(status="passed", live_proof_after=after_proof, seconds=round(seconds, 3), response=response)
        write_evidence(evidence_path, evidence)
        print(json.dumps({"status": "passed", "mode": "offline_one_request", "seconds": evidence["seconds"]}), flush=True)
        return
    try:
        before_proof = live_process_proof(root, binding)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"qualifying live binding failed before smoke: {error}") from error
    evidence = run_full_smoke(client, base_url, root, binding, evidence_path, before_proof)
    print(json.dumps({"status": "passed", "adapter": evidence["winning_adapter"], "warm_seconds": evidence["warm_seconds"], "determinism": evidence["determinism"]}), flush=True)


if __name__ == "__main__":
    main()
