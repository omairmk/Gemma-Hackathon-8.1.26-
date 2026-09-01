#!/usr/bin/env python3
"""Run the pinned Qwen3-VL snapshot locally as a host semantic proxy.

This is deliberately not a substitute for the iPhone Swift/MLX lane. It uses
the shared Swift helper to prepare the same 512-pixel derivative and to run
the production parser/fusion, but MLX-VLM Python has a different runtime and
its processor tensor is not the app's Swift tensor. All emitted evidence is
therefore marked NOT_DEVICE_QUALIFIED.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.metadata
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
from typing import Any, NamedTuple, Optional


ROUTE = "host_python_mlx_semantic_proxy"
QUALIFICATION = "NOT_DEVICE_QUALIFIED; Python MLX-VLM runtime differs from app Swift/MLX"
EXPECTED_FIELDS = ["subject", "bristol", "mixed", "color", "red", "black", "glossy"]
OPAQUE_FIXTURE_NAME = re.compile(r"^[0-9a-f]{20}\.png$")


class FixtureSelection(NamedTuple):
    fixture_id: str
    path: Path
    sha256: str


class SelectionBundle(NamedTuple):
    fixtures: list[FixtureSelection]
    dev_manifest_path: Optional[Path] = None
    dev_manifest_sha256: Optional[str] = None


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_clean_output(directory: Path) -> None:
    if directory.exists() and any(directory.iterdir()):
        raise RuntimeError(f"output directory must be empty: {directory}")
    directory.mkdir(parents=True, exist_ok=True)


def version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "MISSING"


def repository_root() -> Path:
    """Return the repository containing this script, independent of caller cwd."""
    return Path(__file__).resolve().parents[1]


def reject_holdout_path(path: Path) -> None:
    if any("holdout" in component.lower() for component in path.resolve().parts):
        raise RuntimeError(f"holdout input is forbidden in DEV-only host batch mode: {path}")


def select_fixtures(
    explicit_fixtures: Optional[list[Path]], dev_manifest: Optional[Path]
) -> SelectionBundle:
    """Resolve only explicit inputs or a fixture-sets-v2 DEV manifest.

    Holdout paths are rejected before a manifest is opened. A DEV manifest is
    admitted only if it is explicitly synthetic, set=dev, and every opaque
    source filename and source hash matches the manifest.
    """
    if dev_manifest is not None:
        manifest_path = dev_manifest.resolve()
        reject_holdout_path(manifest_path)
        if not manifest_path.is_file():
            raise RuntimeError(f"DEV manifest does not exist: {manifest_path}")
        manifest: dict[str, Any] = json.loads(manifest_path.read_text())
        if manifest.get("schema") != "gi-qwen-fixture-manifest-v2":
            raise RuntimeError("--dev-manifest must use gi-qwen-fixture-manifest-v2")
        if manifest.get("set") != "dev" or manifest.get("synthetic_only") is not True:
            raise RuntimeError("--dev-manifest must declare set=dev and synthetic_only=true")
        images = manifest.get("images")
        if not isinstance(images, list) or not images:
            raise RuntimeError("DEV manifest images must be a nonempty list")
        selections: list[FixtureSelection] = []
        for item in images:
            filename = item.get("file") if isinstance(item, dict) else None
            declared_sha = item.get("sha256") if isinstance(item, dict) else None
            if not isinstance(filename, str) or not OPAQUE_FIXTURE_NAME.fullmatch(filename):
                raise RuntimeError("DEV manifest fixture filenames must be opaque 20-hex PNG names")
            if not isinstance(declared_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", declared_sha):
                raise RuntimeError(f"invalid declared source hash for fixture {filename}")
            fixture = (manifest_path.parent / filename).resolve()
            reject_holdout_path(fixture)
            if fixture.parent != manifest_path.parent.resolve() or not fixture.is_file():
                raise RuntimeError(f"DEV fixture must be beside its manifest: {filename}")
            actual_sha = sha256_path(fixture)
            if actual_sha != declared_sha:
                raise RuntimeError(f"DEV fixture source hash mismatch: {filename}")
            selections.append(FixtureSelection(filename[:-4], fixture, actual_sha))
        if len({item.fixture_id for item in selections}) != len(selections):
            raise RuntimeError("DEV manifest fixture identities must be unique")
        return SelectionBundle(selections, manifest_path, sha256_path(manifest_path))

    if not explicit_fixtures:
        raise RuntimeError("at least one --fixture or one --dev-manifest is required")
    selections = []
    for raw_path in explicit_fixtures:
        fixture = raw_path.resolve()
        reject_holdout_path(fixture)
        if not fixture.is_file():
            raise RuntimeError(f"fixture does not exist: {fixture}")
        source_sha = sha256_path(fixture)
        opaque_id = fixture.stem if OPAQUE_FIXTURE_NAME.fullmatch(fixture.name) else source_sha[:20]
        selections.append(FixtureSelection(opaque_id, fixture, source_sha))
    if len({item.fixture_id for item in selections}) != len(selections):
        raise RuntimeError("selected fixtures must have unique source identities")
    return SelectionBundle(selections)


def run(
    command: list[str], *, capture: bool = False, cwd: Optional[Path] = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=capture, cwd=cwd)


def prepare_fixture(
    selection: FixtureSelection, output: Path, swift_bin: str, repo_root: Path
) -> dict[str, Any]:
    prepared = run([
        swift_bin, "run", "Qwen3HostEvidenceFuse", "prepare",
        "--input", str(selection.path), "--output-dir", str(output),
    ], capture=True, cwd=repo_root)
    preparation: dict[str, Any] = json.loads(prepared.stdout)
    if preparation.get("sourceImageSHA256") != selection.sha256:
        raise RuntimeError(f"shared preparation source hash mismatch: {selection.fixture_id}")
    prompts = preparation.get("prompts")
    if not isinstance(prompts, list) or [item.get("field") for item in prompts] != EXPECTED_FIELDS:
        raise RuntimeError(f"shared preparation did not emit exact seven ordered prompts: {selection.fixture_id}")
    if any(not item.get("prompt") or not item.get("promptSHA256") for item in prompts):
        raise RuntimeError(f"shared preparation emitted incomplete prompt evidence: {selection.fixture_id}")
    (output / "preparation.json").write_text(
        json.dumps(preparation, indent=2, sort_keys=True) + "\n"
    )
    return preparation


def generate_fields(
    preparation: dict[str, Any], model: Any, processor: Any,
    stream_generate: Any, apply_chat_template: Any,
) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = []
    derivative = preparation["derivativePNGPath"]
    for ordinal, prompt_info in enumerate(preparation["prompts"], start=1):
        field_started = time.perf_counter()
        tokens: list[int] = []
        fragments: list[str] = []
        last: Any = None
        # One independent generation per field. No prompt or vision cache is
        # passed between calls, matching the app lane's fresh nil cache intent.
        formatted_prompt = apply_chat_template(
            processor, model.config, prompt_info["prompt"],
            add_generation_prompt=True, num_images=1,
        )
        for result in stream_generate(
            model, processor, formatted_prompt, image=derivative,
            max_tokens=8, temperature=0.0, top_p=1.0, seed=0,
            prefill_step_size=512, verbose=False,
        ):
            last = result
            if result.token is not None:
                token = result.token.item() if hasattr(result.token, "item") else int(result.token)
                tokens.append(int(token))
            fragments.append(result.text)
        raw_text = "".join(fragments)
        raw_bytes = raw_text.encode("utf-8")
        fields.append({
            "field": prompt_info["field"],
            "prompt": prompt_info["prompt"],
            "prompt_sha256": prompt_info["promptSHA256"],
            "runtime_formatted_prompt": formatted_prompt,
            "raw_text": raw_text,
            "raw_utf8_base64": base64.b64encode(raw_bytes).decode("ascii"),
            "raw_utf8_sha256": hashlib.sha256(raw_bytes).hexdigest(),
            "raw_token_ids": tokens,
            "stop_reason": getattr(last, "finish_reason", "unknown") if last else "no_generation",
            "latency_milliseconds": max(1, round((time.perf_counter() - field_started) * 1000)),
            "prompt_tokens": getattr(last, "prompt_tokens", None) if last else None,
            "generation_tokens": getattr(last, "generation_tokens", None) if last else None,
            "peak_memory_gb": getattr(last, "peak_memory", None) if last else None,
            "model_call_ordinal": ordinal,
            "used_fresh_generation_cache": True,
        })
    validate_field_evidence(fields)
    return fields


def validate_field_evidence(fields: list[dict[str, Any]]) -> None:
    if [item.get("field") for item in fields] != EXPECTED_FIELDS:
        raise RuntimeError("model evidence must contain exact seven ordered fields")
    for ordinal, item in enumerate(fields, start=1):
        raw_text = item.get("raw_text")
        if not isinstance(raw_text, str) or not raw_text.strip():
            raise RuntimeError(f"empty raw model text for field {item.get('field')}")
        raw_bytes = raw_text.encode("utf-8")
        if item.get("raw_utf8_sha256") != hashlib.sha256(raw_bytes).hexdigest():
            raise RuntimeError(f"raw model hash mismatch for field {item.get('field')}")
        if not item.get("raw_token_ids") or not all(isinstance(token, int) for token in item["raw_token_ids"]):
            raise RuntimeError(f"missing raw token evidence for field {item.get('field')}")
        if item.get("model_call_ordinal") != ordinal:
            raise RuntimeError(f"model call ordinal mismatch for field {item.get('field')}")
        if not isinstance(item.get("latency_milliseconds"), int) or item["latency_milliseconds"] <= 0:
            raise RuntimeError(f"missing latency evidence for field {item.get('field')}")
        if item.get("used_fresh_generation_cache") is not True:
            raise RuntimeError(f"fresh-cache evidence missing for field {item.get('field')}")


def fuse_fixture(
    output: Path, preparation: dict[str, Any], fields: list[dict[str, Any]],
    swift_bin: str, repo_root: Path,
) -> dict[str, Any]:
    fusion_input = {
        "preparation": preparation,
        "fields": [{
            "field": item["field"], "rawText": item["raw_text"],
            "rawTokenIDs": item["raw_token_ids"],
            "latencyMilliseconds": item["latency_milliseconds"],
            "stopReason": item["stop_reason"],
        } for item in fields],
    }
    fusion_input_path = output / "fusion-input.json"
    fusion_input_path.write_text(json.dumps(fusion_input, indent=2, sort_keys=True) + "\n")
    fused_path = output / "fused-evidence.json"
    run([swift_bin, "run", "Qwen3HostEvidenceFuse", "fuse",
         "--input", str(fusion_input_path), "--output", str(fused_path)], cwd=repo_root)
    fused: dict[str, Any] = json.loads(fused_path.read_text())
    fused_fields = fused.get("runEvidence", {}).get("fields", [])
    if fused.get("schemaVersion") != "qwen3-host-semantic-proxy-evidence-v1":
        raise RuntimeError("shared Swift fusion emitted an unexpected schema")
    if [item.get("field") for item in fused_fields] != EXPECTED_FIELDS:
        raise RuntimeError("shared Swift fusion did not retain exact seven ordered fields")
    if any(item.get("qualified") is not False for item in fused_fields):
        raise RuntimeError("host proxy field escaped the forced-unqualified boundary")
    return fused


def run_fixture(
    selection: FixtureSelection, output: Path, *, model: Any, processor: Any,
    stream_generate: Any, apply_chat_template: Any, mx: Any,
    swift_bin: str, repo_root: Path, snapshot: Path, load_ms: int,
) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=True)
    preparation = prepare_fixture(selection, output, swift_bin, repo_root)
    fields = generate_fields(preparation, model, processor, stream_generate, apply_chat_template)
    host = {
        "schema_version": "qwen3-host-semantic-proxy-run-v1",
        "route": ROUTE,
        "qualification": QUALIFICATION,
        "fixture_id": selection.fixture_id,
        "fixture_path": str(selection.path),
        "fixture_sha256": selection.sha256,
        "model_id": "mlx-community/Qwen3-VL-2B-Instruct-4bit",
        "model_revision": "9c4f5209e57b31f4b9dfba735de3fb983739c9cc",
        "snapshot_path": str(snapshot),
        "snapshot_model_safetensors_sha256": sha256_path(snapshot / "model.safetensors"),
        "preprocessing": preparation,
        "runtime": {
            "python": sys.version,
            "platform": platform.platform(),
            "mlx": version("mlx"), "mlx_vlm": version("mlx-vlm"),
            "mlx_lm": version("mlx-lm"), "transformers": version("transformers"),
            "mlx_peak_memory_gb_after_run": mx.get_peak_memory() / 1e9,
        },
        "model_load_latency_milliseconds": load_ms,
        "model_loaded_once_for_batch": True,
        "fields": fields,
    }
    raw_path = output / "raw-per-field.json"
    raw_path.write_text(json.dumps(host, indent=2, sort_keys=True) + "\n")
    fused = fuse_fixture(output, preparation, fields, swift_bin, repo_root)
    return {
        "fixture_id": selection.fixture_id,
        "source_sha256": selection.sha256,
        "prepared_png_sha256": preparation["derivativePNGSHA256"],
        "prepared_rgba_sha256": preparation["derivative"]["derivativeRGBASHA256"],
        "prompt_set_sha256": fused["promptSetSHA256"],
        "raw_per_field_sha256": sha256_path(raw_path),
        "fused_evidence_sha256": sha256_path(output / "fused-evidence.json"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-root", required=True, type=Path,
                        help="parent containing snapshot/ and VerifyModelSnapshot.py")
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--fixture", action="append", type=Path,
        help="synthetic DEV fixture; repeat for a selected batch (legacy single-fixture form remains valid)",
    )
    selection.add_argument(
        "--dev-manifest", type=Path,
        help="fixture-sets-v2 DEV manifest; holdout manifests and paths are rejected",
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--swift-bin", default="swift")
    arguments = parser.parse_args()

    model_root = arguments.model_root.resolve()
    snapshot = model_root / "snapshot"
    output = arguments.output_dir.resolve()
    verifier = model_root / "VerifyModelSnapshot.py"
    repo_root = repository_root()
    if not snapshot.is_dir() or not verifier.is_file():
        raise RuntimeError("model root must contain snapshot/ and VerifyModelSnapshot.py")
    selected = select_fixtures(arguments.fixture, arguments.dev_manifest)
    require_clean_output(output)

    verification = run([sys.executable, str(verifier), str(model_root)], capture=True)
    (output / "snapshot-verification.tsv").write_text(verification.stdout)
    if "verification=PASS" not in verification.stdout:
        raise RuntimeError("exact model snapshot verification did not report PASS")

    # Import and load exactly once after snapshot verification. Each fixture
    # still gets independent preprocessing and seven fresh-cache generations.
    import mlx.core as mx
    from mlx_vlm import load
    from mlx_vlm.generate.dispatch import stream_generate
    from mlx_vlm.prompt_utils import apply_chat_template

    started = time.perf_counter()
    model, processor = load(str(snapshot), lazy=False, strict=True)
    load_ms = max(1, round((time.perf_counter() - started) * 1000))
    is_batch = len(selected.fixtures) > 1 or selected.dev_manifest_path is not None
    summaries: list[dict[str, Any]] = []
    for item in selected.fixtures:
        fixture_output = output / item.fixture_id if is_batch else output
        summary = run_fixture(
            item, fixture_output, model=model, processor=processor,
            stream_generate=stream_generate, apply_chat_template=apply_chat_template, mx=mx,
            swift_bin=arguments.swift_bin, repo_root=repo_root, snapshot=snapshot, load_ms=load_ms,
        )
        summary["artifact_directory"] = item.fixture_id if is_batch else "."
        summaries.append(summary)

    if is_batch:
        batch_manifest = {
            "schema_version": "qwen3-host-semantic-proxy-dev-batch-v1",
            "route": ROUTE,
            "qualification": QUALIFICATION,
            "scope": "DEV SYNTHETIC HOST SEMANTIC PROXY ONLY; NOT DEVICE OR RELEASE EVIDENCE",
            "model_id": "mlx-community/Qwen3-VL-2B-Instruct-4bit",
            "model_revision": "9c4f5209e57b31f4b9dfba735de3fb983739c9cc",
            "snapshot_model_safetensors_sha256": sha256_path(snapshot / "model.safetensors"),
            "model_load_count": 1,
            "model_load_latency_milliseconds": load_ms,
            "dev_manifest_path": str(selected.dev_manifest_path) if selected.dev_manifest_path else None,
            "dev_manifest_sha256": selected.dev_manifest_sha256,
            "fixture_count": len(summaries),
            "fixtures": summaries,
        }
        (output / "batch-manifest.json").write_text(
            json.dumps(batch_manifest, indent=2, sort_keys=True) + "\n"
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"FAILED subprocess: {error.cmd} exit={error.returncode}", file=sys.stderr)
        raise SystemExit(error.returncode)
    except Exception as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(2)
