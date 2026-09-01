#!/usr/bin/env python3
"""Run the fixed 28-image synthetic DEV Qwen3-VL A/B campaign once.

This runner is deliberately narrow. It accepts only a sealed 28-image DEV
admission/labels pair, verifies the exact local Qwen3-VL snapshot, prepares
each source through the shared Swift image path, and runs exactly two fixed
configurations in one model load:

* A: 28 × seven decomposed shared prompts at app-derived 512 (196 calls).
* B: 28 × subject/Bristol/color prompts at host-only 768 (84 calls).

It has no retry, resume, prompt-variant, resolution-variant, or extra-call
mode. The 512 derivative is the shared Swift app preparation. The 768
derivative is explicitly HOST_ONLY and is neither app nor device evidence.
Every result remains synthetic host evidence only; it is not clinical,
physical-device, TestFlight, or App Store qualification.
"""

from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import hashlib
import importlib.metadata
import importlib.util
import json
from dataclasses import dataclass
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import threading
import time
from typing import Any, Callable, Iterable, Mapping, Optional


MODEL_ID = "mlx-community/Qwen3-VL-2B-Instruct-4bit"
MODEL_REVISION = "9c4f5209e57b31f4b9dfba735de3fb983739c9cc"
ROUTE = "host_python_mlx_dev_ab"
QUALIFICATION = (
    "SYNTHETIC_DEV_HOST_ONLY; NOT_DEVICE_QUALIFIED; NOT_CLINICAL; "
    "NOT_TESTFLIGHT_OR_APP_STORE_EVIDENCE"
)
ADMISSION_SCHEMA = "gi-mild-utility-admission-manifest-v2"
LABELS_SCHEMA = "gi-mild-utility-evaluation-labels-v2"
RUN_SCHEMA = "gi-mild-utility-run-record-v2"
CAMPAIGN_SCHEMA = "qwen3-host-dev-ab-campaign-v1"
EVALUATOR_RELATIVE_PATH = Path(
    "handoff-2026-08-22-linux-surface/qwen-mild-utility-v3-2026-08-31/"
    "evaluator/score_mild_utility_v3.py"
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MAX_CAMPAIGN_CALLS = 280
MAX_TOKENS_PER_CALL = 8
CALL_TIMEOUT_MILLISECONDS = 120_000
MODEL_FIELDS = ("subject", "bristol", "mixed", "color", "red", "black", "glossy")
EVALUATOR_FIELD = {
    "subject": "subject",
    "bristol": "bristol_band",
    "mixed": "mixed",
    "color": "color",
    "red": "red",
    "black": "dark_black",
    "glossy": "glossy_tarlike",
}
VALUE_FIELDS = ("subject", "color", "bristol_band", "red", "dark_black", "glossy_tarlike")
SAFETY_FIELDS = ("red", "dark_black", "glossy_tarlike")


@dataclass(frozen=True)
class Configuration:
    label: str
    configuration_id: str
    resolution: int
    invoked_model_fields: tuple[str, ...]
    preparation_scope: str

    @property
    def invoked_evaluator_fields(self) -> tuple[str, ...]:
        return tuple(EVALUATOR_FIELD[field] for field in self.invoked_model_fields)


CONFIGURATIONS = (
    Configuration(
        label="A",
        configuration_id="qwen3vl_decomposed_512",
        resolution=512,
        invoked_model_fields=MODEL_FIELDS,
        preparation_scope="APP_DERIVED_512_SHARED_SWIFT",
    ),
    Configuration(
        label="B",
        configuration_id="qwen3vl_subset_768",
        resolution=768,
        invoked_model_fields=("subject", "bristol", "color"),
        preparation_scope="HOST_ONLY_768_NOT_APP_OR_DEVICE_EQUIVALENT",
    ),
)


class ContractFailure(RuntimeError):
    """A precondition or emitted receipt was not trustworthy enough to run."""


class GenerationTimeout(TimeoutError):
    """A synchronous model call exceeded its fixed wall-clock budget."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractFailure(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def object_sha256(value: Any) -> str:
    return sha256_bytes(canonical_json(value).encode("utf-8"))


def artifact_sha256(value: Mapping[str, Any]) -> str:
    return object_sha256({key: child for key, child in value.items() if key != "artifact_sha256"})


def seal_artifact(value: dict[str, Any]) -> dict[str, Any]:
    value["artifact_sha256"] = artifact_sha256(value)
    return value


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle, object_pairs_hook=unique_object)
    except (OSError, json.JSONDecodeError) as error:
        raise ContractFailure(f"could not read JSON artifact {path}: {error}") from error
    require(isinstance(value, dict), f"artifact must be an object: {path}")
    return value


def write_json(path: Path, value: Mapping[str, Any]) -> str:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    actual = sha256_path(path)
    require(actual == sha256_bytes(path.read_bytes()), f"output hash mismatch after write: {path}")
    return actual


def reject_holdout_path(path: Path) -> None:
    if any("holdout" in component.lower() for component in path.resolve().parts):
        raise ContractFailure(f"holdout path is forbidden: {path}")


@dataclass(frozen=True)
class Fixture:
    fixture_id: str
    source_sha256: str
    path: Path


@dataclass(frozen=True)
class DevInputs:
    dataset_id: str
    admission: dict[str, Any]
    labels: dict[str, Any]
    fixtures: tuple[Fixture, ...]


def load_evaluator_validator(repo_root: Path) -> Any:
    """Load the versioned evaluator so its admission rules stay authoritative."""
    evaluator_path = repo_root / EVALUATOR_RELATIVE_PATH
    require(evaluator_path.is_file(), f"evaluator validator is unavailable: {evaluator_path}")
    spec = importlib.util.spec_from_file_location("qwen3_mild_utility_evaluator_v2_preflight", evaluator_path)
    require(spec is not None and spec.loader is not None, "evaluator validator must be importable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    require(module.ADMISSION_SCHEMA == ADMISSION_SCHEMA, "runner/evaluator admission schema drift")
    require(module.LABELS_SCHEMA == LABELS_SCHEMA, "runner/evaluator labels schema drift")
    return module


def validate_evaluator_preflight(
    *, blind_input_path: Path, blind_review_path: Path, admission_path: Path, labels_path: Path,
    repo_root: Path,
) -> tuple[dict[str, Any], dict[str, Any], Mapping[str, Mapping[str, Any]]]:
    """Run the evaluator's complete frozen-DEV admission/labels validation before model import."""
    for path in (blind_input_path, blind_review_path, admission_path, labels_path):
        reject_holdout_path(path)
    blind_input = load_json(blind_input_path)
    blind_review = load_json(blind_review_path)
    admission = load_json(admission_path)
    labels = load_json(labels_path)
    evaluator = load_evaluator_validator(repo_root)
    try:
        validated_blind_input, blind_by_id = evaluator.validate_blind_input(blind_input)
        validated_blind_review, review_by_id = evaluator.validate_blind_review(
            blind_review, validated_blind_input, blind_by_id
        )
        validated_admission, admitted_by_id = evaluator.validate_admission(
            admission, validated_blind_input, validated_blind_review, blind_by_id, review_by_id
        )
        validated_labels, labels_by_id = evaluator.validate_labels(
            labels, validated_admission, admitted_by_id
        )
    except Exception as error:
        raise ContractFailure(f"evaluator preflight rejected DEV admission/labels: {error}") from error
    return validated_admission, validated_labels, labels_by_id


def load_dev_inputs(
    blind_input_path: Path,
    blind_review_path: Path,
    admission_path: Path,
    labels_path: Path,
    fixture_root: Path,
) -> DevInputs:
    for path in (blind_input_path, blind_review_path, admission_path, labels_path, fixture_root):
        reject_holdout_path(path)
    require(fixture_root.is_dir(), "fixture root must be a directory")
    admission, labels, labels_by_id = validate_evaluator_preflight(
        blind_input_path=blind_input_path,
        blind_review_path=blind_review_path,
        admission_path=admission_path,
        labels_path=labels_path,
        repo_root=repository_root(),
    )
    fixtures: list[Fixture] = []
    for fixture_id, row in labels_by_id.items():
        source_sha = row["source_sha256"]
        fixture_path = (fixture_root / f"{fixture_id}.png").resolve()
        reject_holdout_path(fixture_path)
        require(fixture_path.parent == fixture_root.resolve() and fixture_path.is_file(), f"missing opaque fixture {fixture_id}.png")
        require(sha256_path(fixture_path) == source_sha, f"fixture source hash mismatch: {fixture_id}")
        fixtures.append(Fixture(fixture_id, source_sha, fixture_path))
    expected_names = {f"{fixture.fixture_id}.png" for fixture in fixtures}
    actual_names = {entry.name for entry in fixture_root.iterdir() if entry.is_file()}
    require(actual_names == expected_names, "fixture root must contain exactly the sealed 28 opaque PNG fixtures")
    return DevInputs(admission["dataset_id"], admission, labels, tuple(fixtures))


@dataclass(frozen=True)
class PlannedCall:
    global_ordinal: int
    configuration_id: str
    fixture_id: str
    model_field: str
    fixture_call_ordinal: int


def build_plan(fixtures: Iterable[Fixture]) -> tuple[PlannedCall, ...]:
    selection = tuple(fixtures)
    require(len(selection) == 28, "fixed campaign requires exactly 28 fixtures")
    calls: list[PlannedCall] = []
    global_ordinal = 1
    for config in CONFIGURATIONS:
        for fixture in selection:
            for fixture_ordinal, field in enumerate(config.invoked_model_fields, start=1):
                calls.append(PlannedCall(global_ordinal, config.configuration_id, fixture.fixture_id, field, fixture_ordinal))
                global_ordinal += 1
    require(len(calls) == MAX_CAMPAIGN_CALLS, "fixed plan must contain exactly 280 calls")
    require([call.global_ordinal for call in calls] == list(range(1, MAX_CAMPAIGN_CALLS + 1)), "global ordinals are not contiguous")
    return tuple(calls)


def plan_artifact(plan: tuple[PlannedCall, ...], inputs: DevInputs) -> dict[str, Any]:
    value = {
        "schema": "qwen3-host-dev-ab-plan-v1",
        "dataset_id": inputs.dataset_id,
        "admission_manifest_sha256": inputs.admission["artifact_sha256"],
        "evaluation_labels_sha256": inputs.labels["artifact_sha256"],
        "fixed_order": [config.configuration_id for config in CONFIGURATIONS],
        "calls": [
            {
                "global_ordinal": call.global_ordinal,
                "configuration_id": call.configuration_id,
                "fixture_id": call.fixture_id,
                "model_field": call.model_field,
                "fixture_call_ordinal": call.fixture_call_ordinal,
            }
            for call in plan
        ],
    }
    return seal_artifact(value)


def run_command(command: list[str], *, cwd: Optional[Path] = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=True, cwd=cwd)


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def preflight_canvas_size(swift_bin: str, repo_root: Path, canvas_size: int) -> dict[str, Any]:
    result = run_command(
        [swift_bin, "run", "Qwen3HostEvidenceFuse", "preflight", "--canvas-size", str(canvas_size)],
        cwd=repo_root,
    )
    try:
        evidence = json.loads(result.stdout, object_pairs_hook=unique_object)
    except json.JSONDecodeError as error:
        raise ContractFailure(f"shared Swift preflight returned invalid JSON for {canvas_size}") from error
    require(evidence == {
        "canvasSize": canvas_size,
        "qualification": (
            "APP_DERIVED_512_PREPARATION_SHARED_SWIFT_ONLY" if canvas_size == 512
            else "HOST_ONLY_768_PREPARATION_NOT_APP_OR_DEVICE_EQUIVALENT"
        ),
        "schemaVersion": "qwen3-host-dev-ab-preflight-v1",
        "supported": True,
    }, f"shared Swift preflight mismatch for {canvas_size}")
    return evidence


def validate_snapshot(model_root: Path, output: Path) -> tuple[Path, str, str]:
    reject_holdout_path(model_root)
    snapshot = model_root / "snapshot"
    verifier = model_root / "VerifyModelSnapshot.py"
    require(snapshot.is_dir() and verifier.is_file(), "model root must contain snapshot/ and VerifyModelSnapshot.py")
    verification = run_command([sys.executable, str(verifier), str(model_root)])
    verification_path = output / "snapshot-verification.tsv"
    verification_path.write_text(verification.stdout, encoding="utf-8")
    require("verification=PASS" in verification.stdout, "snapshot verification did not report PASS")
    safetensors = snapshot / "model.safetensors"
    require(safetensors.is_file(), "verified snapshot lacks model.safetensors")
    return snapshot, sha256_path(safetensors), sha256_path(verification_path)


def prepare_fixture(
    fixture: Fixture,
    config: Configuration,
    output: Path,
    swift_bin: str,
    repo_root: Path,
) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=False)
    result = run_command(
        [
            swift_bin, "run", "Qwen3HostEvidenceFuse", "prepare",
            "--input", str(fixture.path), "--output-dir", str(output),
            "--canvas-size", str(config.resolution),
        ],
        cwd=repo_root,
    )
    try:
        preparation = json.loads(result.stdout, object_pairs_hook=unique_object)
    except json.JSONDecodeError as error:
        raise ContractFailure(f"shared preparation returned invalid JSON for {fixture.fixture_id}") from error
    require(preparation.get("sourceImageSHA256") == fixture.source_sha256, f"source hash mismatch in preparation for {fixture.fixture_id}")
    derivative = preparation.get("derivative")
    require(isinstance(derivative, dict), "preparation lacks derivative provenance")
    require(derivative.get("derivativeWidth") == config.resolution and derivative.get("derivativeHeight") == config.resolution,
            f"prepared canvas mismatch for {fixture.fixture_id}")
    expected_version = (
        "qwen3vl-hybrid-512-v2-preprocessing-evidence"
        if config.resolution == 512
        else "host-only-qwen3vl-hybrid-768-v1"
    )
    require(preparation.get("preprocessingVersion") == expected_version, f"preparation version mismatch for {fixture.fixture_id}")
    preprocessing_evidence = preparation.get("preprocessingEvidence")
    require(isinstance(preprocessing_evidence, dict), "preparation lacks preprocessing evidence")
    require(
        preprocessing_evidence.get("deterministicDerivativePixelWidth") == 512
        and preprocessing_evidence.get("deterministicDerivativePixelHeight") == 512,
        "deterministic derivative must remain exactly 512x512",
    )
    require(
        SHA256.fullmatch(
            str(preprocessing_evidence.get("deterministicDerivativeRGBASHA256", ""))
        )
        is not None,
        "deterministic derivative hash is invalid",
    )
    qualification = preparation.get("qualification")
    if config.resolution == 512:
        require(qualification == "NOT_DEVICE_QUALIFIED; app-derived shared Swift 512 preprocessing only", "512 preparation qualification mismatch")
    else:
        require(qualification == "HOST_ONLY_768_PREPARATION_NOT_APP_OR_DEVICE_EQUIVALENT", "768 preparation qualification mismatch")
    prompts = preparation.get("prompts")
    require(isinstance(prompts, list) and [row.get("field") for row in prompts] == list(MODEL_FIELDS),
            "shared preparation prompt order drifted")
    for row in prompts:
        require(isinstance(row.get("prompt"), str) and SHA256.fullmatch(str(row.get("promptSHA256", ""))), "shared prompt evidence invalid")
    derivative_path = Path(str(preparation.get("derivativePNGPath", ""))).resolve()
    require(derivative_path.parent == output.resolve() and derivative_path.is_file(), "prepared image path escaped output")
    require(sha256_path(derivative_path) == preparation.get("derivativePNGSHA256"), "prepared PNG hash mismatch")
    write_json(output / "preparation.json", preparation)
    return preparation


def prompt_set_sha256(preparation: Mapping[str, Any], fields: tuple[str, ...]) -> str:
    prompts = {str(row["field"]): str(row["prompt"]) for row in preparation["prompts"]}
    return sha256_bytes("\n".join(f"{field}|{prompts[field]}" for field in fields).encode("utf-8"))


def configuration_artifact(config: Configuration, preparation: Mapping[str, Any]) -> dict[str, Any]:
    value = {
        "configuration_id": config.configuration_id,
        "resolution": config.resolution,
        "max_tokens_per_call": MAX_TOKENS_PER_CALL,
        "prompt_set_sha256": prompt_set_sha256(preparation, config.invoked_model_fields),
        "invoked_fields": list(config.invoked_evaluator_fields),
        "preparation_scope": config.preparation_scope,
    }
    value["configuration_sha256"] = object_sha256(value)
    return value


def value_shape(value: Any) -> Optional[list[int]]:
    shape = getattr(value, "shape", None)
    if shape is None:
        return None
    try:
        result = [int(item) for item in shape]
    except (TypeError, ValueError):
        return None
    return result if result else None


def processor_evidence(processor: Any, model: Any, formatted_prompt: Any, image_path: str) -> dict[str, Any]:
    """Collect stable, best-effort processor shape/config evidence without a second generation."""
    metadata: dict[str, Any] = {
        "processor_type": type(processor).__name__,
        "model_config_type": type(getattr(model, "config", None)).__name__,
        "formatted_prompt_sha256": sha256_bytes(str(formatted_prompt).encode("utf-8")),
        "prepared_image_path_sha256": sha256_bytes(image_path.encode("utf-8")),
    }
    candidates = [("processor", processor), ("model_config", getattr(model, "config", None))]
    candidates.extend((name, getattr(processor, name, None)) for name in (
        "image_processor", "vision_processor", "processor", "config",
    ))
    for name, candidate in candidates:
        if candidate is None:
            continue
        candidate_shape = value_shape(candidate)
        if candidate_shape is not None:
            metadata[f"{name}_shape"] = candidate_shape
        for grid_name in ("image_grid_thw", "grid_thw", "grid_size", "patch_size", "image_size"):
            grid = getattr(candidate, grid_name, None)
            if grid is None:
                continue
            if isinstance(grid, (list, tuple)) and all(isinstance(item, int) for item in grid):
                metadata[f"{name}_{grid_name}"] = list(grid)
            elif isinstance(grid, int):
                metadata[f"{name}_{grid_name}"] = grid
    # The exact derivative tensor dimensions are independently established by
    # shared Swift provenance. This records what the Python processor exposes
    # without pretending a host MLX tensor is the app's Swift tensor.
    return metadata


@contextmanager
def synchronous_generation_timeout(timeout_milliseconds: int) -> Iterable[None]:
    """Interrupt one synchronous `stream_generate` iteration after a real wall-clock deadline.

    macOS/Python delivers SIGALRM only to the main thread. Refuse an existing
    interval timer instead of replacing it; cancellation and handler restore
    in ``finally`` prevent one call's deadline from affecting the next one.
    """
    require(timeout_milliseconds > 0, "generation timeout must be positive")
    require(hasattr(signal, "setitimer") and hasattr(signal, "SIGALRM"), "SIGALRM timeout is unavailable")
    require(threading.current_thread() is threading.main_thread(), "generation timeout requires the main thread")
    previous_delay, previous_interval = signal.getitimer(signal.ITIMER_REAL)
    require(
        previous_delay == 0.0 and previous_interval == 0.0,
        "generation timeout cannot replace an active process interval timer",
    )
    previous_handler = signal.getsignal(signal.SIGALRM)

    def expired(_signum: int, _frame: Any) -> None:
        raise GenerationTimeout(f"stream_generate exceeded {timeout_milliseconds}ms wall-clock timeout")

    signal.signal(signal.SIGALRM, expired)
    try:
        signal.setitimer(signal.ITIMER_REAL, timeout_milliseconds / 1000.0)
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0.0)
        signal.signal(signal.SIGALRM, previous_handler)


def generate_one(
    *, model: Any, processor: Any, stream_generate: Callable[..., Iterable[Any]],
    apply_chat_template: Callable[..., Any], mx: Any, preparation: Mapping[str, Any],
    field: str, global_ordinal: int, fixture_call_ordinal: int,
    timeout_milliseconds: int = CALL_TIMEOUT_MILLISECONDS,
) -> dict[str, Any]:
    prompt_info = next(row for row in preparation["prompts"] if row["field"] == field)
    started = time.perf_counter()
    formatted_prompt = apply_chat_template(
        processor, model.config, prompt_info["prompt"], add_generation_prompt=True, num_images=1,
    )
    tokens: list[int] = []
    fragments: list[str] = []
    last: Any = None
    timed_out = False
    try:
        with synchronous_generation_timeout(timeout_milliseconds):
            for result in stream_generate(
                model, processor, formatted_prompt, image=preparation["derivativePNGPath"],
                max_tokens=MAX_TOKENS_PER_CALL, temperature=0.0, top_p=1.0, seed=0,
                prefill_step_size=512, verbose=False,
            ):
                last = result
                if result.token is not None:
                    token = result.token.item() if hasattr(result.token, "item") else int(result.token)
                    tokens.append(int(token))
                fragments.append(result.text)
    except GenerationTimeout:
        timed_out = True
    raw_text = "".join(fragments)
    raw_bytes = raw_text.encode("utf-8")
    latency = max(1, round((time.perf_counter() - started) * 1000))
    if not timed_out:
        require(raw_text.strip(), f"empty model output at global ordinal {global_ordinal}")
        require(tokens, f"missing token evidence at global ordinal {global_ordinal}")
    return {
        "model_field": field,
        "global_ordinal": global_ordinal,
        "fixture_call_ordinal": fixture_call_ordinal,
        "prompt": prompt_info["prompt"],
        "prompt_sha256": prompt_info["promptSHA256"],
        "runtime_formatted_prompt": str(formatted_prompt),
        "raw_text": raw_text,
        "raw_utf8_base64": base64.b64encode(raw_bytes).decode("ascii"),
        "raw_utf8_sha256": sha256_bytes(raw_bytes),
        "raw_token_ids": tokens,
        "stop_reason": "timeout" if timed_out else getattr(last, "finish_reason", "unknown") if last else "no_generation",
        "latency_milliseconds": latency,
        "timed_out": timed_out,
        "prompt_tokens": getattr(last, "prompt_tokens", None) if last else None,
        "generation_tokens": getattr(last, "generation_tokens", None) if last else None,
        "generation_peak_memory_gb": getattr(last, "peak_memory", None) if last else None,
        "mlx_peak_memory_bytes": int(mx.get_peak_memory()),
        "processor_evidence": processor_evidence(processor, model, formatted_prompt, preparation["derivativePNGPath"]),
    }


def shared_parse_subset(
    raw_fields: Mapping[str, Mapping[str, Any]], output: Path, swift_bin: str, repo_root: Path
) -> dict[str, Any]:
    input_value = {
        "fields": [
            {"field": field, "rawText": raw_fields[field]["raw_text"]}
            for field in raw_fields
        ]
    }
    input_path = output / "shared-parser-input.json"
    output_path = output / "shared-parser-receipt.json"
    write_json(input_path, input_value)
    run_command(
        [swift_bin, "run", "Qwen3HostEvidenceFuse", "parse-subset", "--input", str(input_path), "--output", str(output_path)],
        cwd=repo_root,
    )
    parsed = load_json(output_path)
    require(parsed.get("schemaVersion") == "qwen3-host-dev-ab-shared-parser-subset-v1", "shared subset parser schema mismatch")
    records = parsed.get("records")
    require(isinstance(records, list) and [row.get("field") for row in records] == list(MODEL_FIELDS), "shared parser field order mismatch")
    invoked = {str(row["field"]): row for row in records if row.get("invoked") is True}
    require(set(invoked) == set(raw_fields), "shared parser invocation receipt mismatch")
    for field in MODEL_FIELDS:
        row = next(item for item in records if item["field"] == field)
        parsed_label = row.get("parsed")
        require(isinstance(parsed_label, dict), "shared parser result missing label")
        if field not in raw_fields:
            require(row.get("invoked") is False and parsed_label.get("label") == "unsure", "uninvoked subset field escaped not_sure")
    return parsed


def parsed_labels(parser_receipt: Mapping[str, Any]) -> dict[str, str]:
    labels: dict[str, str] = {}
    for row in parser_receipt["records"]:
        parsed = row["parsed"]
        label = parsed.get("label") if isinstance(parsed, dict) else None
        disposition = parsed.get("disposition") if isinstance(parsed, dict) else None
        labels[str(row["field"])] = str(label) if disposition in ("accepted", "accepted_prefix") else "unsure"
    require(set(labels) == set(MODEL_FIELDS), "shared parser labels incomplete")
    return labels


def empty_values() -> dict[str, str]:
    return {field: "not_sure" for field in VALUE_FIELDS}


def safety_hints(values: Mapping[str, str]) -> dict[str, str]:
    red_copy = {
        "possible_positive": "AI suggestion: Possible blood-like red material is visible.",
        "no": "AI suggestion: No blood-like red material detected in this photo.",
        "not_sure": "AI suggestion: Unable to determine whether blood-like red material is visible.",
    }
    black_tarry_copy = {
        "possible_positive": "AI suggestion: Possible black or tar-like appearance is visible.",
        "no": "AI suggestion: No black or tar-like appearance detected in this photo.",
        "not_sure": "AI suggestion: Unable to determine whether a black or tar-like appearance is visible.",
    }
    return {
        "red": red_copy[values["red"]],
        "dark_black": black_tarry_copy[values["dark_black"]],
        "glossy_tarlike": black_tarry_copy[values["glossy_tarlike"]],
    }


def stage(values: Mapping[str, str]) -> dict[str, Any]:
    normalized = dict(values)
    require(set(normalized) == set(VALUE_FIELDS), "stage values incomplete")
    for safety in SAFETY_FIELDS:
        require(normalized[safety] in {"possible_positive", "no", "not_sure"}, "invalid appearance suggestion value")
    value = {"values": normalized, "safety_hints": safety_hints(normalized)}
    value["record_sha256"] = object_sha256(value)
    return value


def labels_to_values(labels: Mapping[str, str]) -> dict[str, str]:
    values = empty_values()
    values["subject"] = {"stool": "stool", "nonstool": "control"}.get(labels["subject"], "not_sure")
    values["color"] = {
        "brown": "brown_tan", "yellow": "yellow", "green": "green", "red": "red", "black": "dark_black",
    }.get(labels["color"], "not_sure")
    values["bristol_band"] = {
        "1": "hard", "2": "hard", "3": "formed", "4": "formed",
        "5": "loose_mushy", "6": "loose_mushy", "7": "watery",
    }.get(labels["bristol"], "not_sure")
    for model_field, evaluator_field in (("red", "red"), ("black", "dark_black"), ("glossy", "glossy_tarlike")):
        values[evaluator_field] = {
            "yes": "possible_positive",
            "no": "no",
            "unsure": "not_sure",
        }.get(labels[model_field], "not_sure")
    return values


def deterministic_values(preparation: Mapping[str, Any]) -> dict[str, str]:
    values = empty_values()
    pixels = preparation.get("pixelEvidence")
    require(isinstance(pixels, dict), "preparation lacks pixel evidence")
    values["color"] = {
        "brown": "brown_tan", "light_brown": "brown_tan", "dark_brown": "brown_tan",
        "yellow": "yellow", "green": "green", "red_appearing": "red", "black_appearing": "dark_black",
        "orange": "pale_other", "pale_or_clay_appearing": "pale_other",
    }.get(pixels.get("baseColorCandidate"), "not_sure")
    for source, target in (("localizedRed", "red"), ("localizedBlack", "dark_black"), ("tarryGlossSmear", "glossy_tarlike")):
        values[target] = {
            "high_positive": "possible_positive",
            "high_negative": "no",
        }.get(pixels.get(source), "not_sure")
    return values


def host_fusion_values(
    raw: Mapping[str, str], deterministic: Mapping[str, str], preparation: Mapping[str, Any]
) -> dict[str, str]:
    """Mirror the app's decomposed fusion for no-model scoring and sealed runs."""
    values = empty_values()
    pixels = preparation.get("pixelEvidence")
    require(isinstance(pixels, dict), "preparation lacks pixel evidence")
    if pixels.get("quality") != "usable":
        return values

    color_confidence = pixels.get("baseColorConfidencePPM")
    if (
        isinstance(color_confidence, int)
        and not isinstance(color_confidence, bool)
        and color_confidence >= 550_000
        and raw["color"] != "not_sure"
        and raw["color"] == deterministic["color"]
    ):
        values["color"] = raw["color"]
    for field in ("red", "dark_black"):
        if raw[field] in {"possible_positive", "no"} and raw[field] == deterministic[field]:
            values[field] = raw[field]
    # Match the app's compound tar-like contract: both the black and glossy
    # model heads, and both corresponding pixel cues, must agree on the same
    # concrete Yes or No. Gloss alone never qualifies this field.
    glossy = raw["glossy_tarlike"]
    if (
        glossy in {"possible_positive", "no"}
        and raw["dark_black"] == glossy
        and deterministic["dark_black"] == glossy
        and deterministic["glossy_tarlike"] == glossy
    ):
        values["glossy_tarlike"] = glossy
    return values


def response_record(parser_receipt: Mapping[str, Any], generated: Mapping[str, Mapping[str, Any]]) -> dict[str, bool]:
    invoked_records = [row for row in parser_receipt["records"] if row.get("invoked") is True]
    malformed = any(row["parsed"].get("disposition") == "invalid" for row in invoked_records)
    timed_out = any(record["timed_out"] for record in generated.values())
    return {
        "raw_schema_valid": not malformed,
        "safely_converted_to_not_sure": malformed or timed_out,
        "timed_out": timed_out,
        "malformed": malformed,
        "contradictory": False,
        "missing": False,
    }


def fixture_record(
    fixture: Fixture, config: Configuration, preparation: Mapping[str, Any], generated: Mapping[str, Mapping[str, Any]],
    parser_receipt: Mapping[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    labels = parsed_labels(parser_receipt)
    raw_values = labels_to_values(labels)
    deterministic = deterministic_values(preparation)
    fused = host_fusion_values(raw_values, deterministic, preparation)
    response = response_record(parser_receipt, generated)
    displayed = empty_values() if response["safely_converted_to_not_sure"] else fused
    raw_outputs: dict[str, Any] = {}
    campaign_receipts: list[dict[str, Any]] = []
    for field in config.invoked_model_fields:
        evidence = generated[field]
        evaluator_field = EVALUATOR_FIELD[field]
        raw_outputs[evaluator_field] = {
            "utf8_base64": evidence["raw_utf8_base64"],
            "sha256": evidence["raw_utf8_sha256"],
            "model_call_ordinal": evidence["fixture_call_ordinal"],
        }
        campaign_receipts.append({
            "global_ordinal": evidence["global_ordinal"],
            "configuration_id": config.configuration_id,
            "fixture_id": fixture.fixture_id,
            "model_field": field,
            "raw_utf8_sha256": evidence["raw_utf8_sha256"],
            "receipt_sha256": object_sha256(evidence),
        })
    record = {
        "fixture_id": fixture.fixture_id,
        "source_sha256": fixture.source_sha256,
        "prepared_sha256": preparation["derivativePNGSHA256"],
        "request_id": f"req-{config.label.lower()}-{fixture.fixture_id}",
        "raw_outputs": raw_outputs,
        "response": response,
        "model_call_count": len(config.invoked_model_fields),
        "latency_milliseconds": sum(record["latency_milliseconds"] for record in generated.values()),
        "stages": {
            "raw": stage(raw_values),
            "parsed": stage(raw_values),
            "deterministic": stage(deterministic),
            "fused": stage(fused),
            "displayed": stage(displayed),
        },
    }
    return record, campaign_receipts


def write_model_evidence(
    *, fixture: Fixture, config: Configuration, preparation: Mapping[str, Any],
    generated: Mapping[str, Mapping[str, Any]], output: Path,
) -> dict[str, Any]:
    """Persist complete per-call host evidence before parser/fusion conversion."""
    value = {
        "schema": "qwen3-host-dev-ab-model-evidence-v1",
        "route": ROUTE,
        "qualification": QUALIFICATION,
        "configuration_id": config.configuration_id,
        "preparation_scope": config.preparation_scope,
        "fixture_id": fixture.fixture_id,
        "source_sha256": fixture.source_sha256,
        "prepared_png_sha256": preparation["derivativePNGSHA256"],
        "prepared_rgba_sha256": preparation["derivative"]["derivativeRGBASHA256"],
        "shared_prepared_rgba_tensor_shape": [
            preparation["derivative"]["derivativeWidth"],
            preparation["derivative"]["derivativeHeight"],
            4,
        ],
        "calls": [generated[field] for field in config.invoked_model_fields],
    }
    value = seal_artifact(value)
    write_json(output / "model-evidence.json", value)
    require(load_json(output / "model-evidence.json").get("artifact_sha256") == artifact_sha256(load_json(output / "model-evidence.json")),
            "model evidence output hash mismatch")
    return value


def run_record(
    *, inputs: DevInputs, config: Configuration, preparation: Mapping[str, Any], fixtures: list[dict[str, Any]],
    model_safetensors_sha256: str, plan_sha256: str,
) -> dict[str, Any]:
    config_value = configuration_artifact(config, preparation)
    # The evaluator schema purposefully has no qualifier field. The campaign
    # receipt carries the host-only boundary, while this object stays schema-exact.
    schema_configuration = {key: config_value[key] for key in (
        "configuration_id", "configuration_sha256", "resolution", "max_tokens_per_call", "prompt_set_sha256", "invoked_fields",
    )}
    value = {
        "schema": RUN_SCHEMA,
        "dataset_id": inputs.dataset_id,
        "split": "dev",
        "admission_manifest_sha256": inputs.admission["artifact_sha256"],
        "evaluation_labels_sha256": inputs.labels["artifact_sha256"],
        "plan_sha256": plan_sha256,
        "campaign_id": "qwen3vl-dev-ab-280-v1",
        "configuration": schema_configuration,
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION, "snapshot_sha256": model_safetensors_sha256},
        "model_load_count": 1,
        "generation_count": sum(row["model_call_count"] for row in fixtures),
        "campaign_generation_count": MAX_CAMPAIGN_CALLS,
        "fixtures": fixtures,
    }
    return seal_artifact(value)


def runtime_versions() -> dict[str, str]:
    def version(name: str) -> str:
        try:
            return importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            return "MISSING"
    return {
        "python": sys.version,
        "platform": platform.platform(),
        "mlx": version("mlx"),
        "mlx_vlm": version("mlx-vlm"),
        "mlx_lm": version("mlx-lm"),
        "transformers": version("transformers"),
    }


def source_hashes(repo_root: Path) -> dict[str, str]:
    paths = {
        "runner": Path(__file__).resolve(),
        "swift_host_tool": repo_root / "Tools/Qwen3HostEvidenceFuse/main.swift",
        "shared_preparer_and_prompt_contract": repo_root / "Sources/GITimelineCore/PhotoSuggestionHybrid.swift",
    }
    for path in paths.values():
        require(path.is_file(), f"required tool source is unavailable: {path}")
    return {name: sha256_path(path) for name, path in paths.items()}


def require_clean_output(output: Path) -> None:
    if output.exists() and any(output.iterdir()):
        raise ContractFailure(f"output directory must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)


def execute(arguments: argparse.Namespace) -> int:
    repo_root = repository_root()
    output = arguments.output_dir.resolve()
    reject_holdout_path(output)
    require_clean_output(output)
    inputs = load_dev_inputs(
        arguments.blind_input,
        arguments.blind_review,
        arguments.admission_manifest,
        arguments.evaluation_labels,
        arguments.fixture_root.resolve(),
    )
    plan = build_plan(inputs.fixtures)
    plan_value = plan_artifact(plan, inputs)
    write_json(output / "campaign-plan.json", plan_value)
    for config in CONFIGURATIONS:
        preflight_canvas_size(arguments.swift_bin, repo_root, config.resolution)
    snapshot, snapshot_sha, verification_sha = validate_snapshot(arguments.model_root.resolve(), output)

    prepared: dict[tuple[str, str], dict[str, Any]] = {}
    for config in CONFIGURATIONS:
        for fixture in inputs.fixtures:
            directory = output / config.label / fixture.fixture_id
            prepared[(config.configuration_id, fixture.fixture_id)] = prepare_fixture(
                fixture, config, directory, arguments.swift_bin, repo_root
            )
    # Preparation is complete and the whole fixed plan is checked before any
    # import/load. A failure above produces zero model generations.
    require(len(plan) == MAX_CAMPAIGN_CALLS, "plan changed after preparation")

    import mlx.core as mx
    from mlx_vlm import load
    from mlx_vlm.generate.dispatch import stream_generate
    from mlx_vlm.prompt_utils import apply_chat_template

    load_started = time.perf_counter()
    model, processor = load(str(snapshot), lazy=False, strict=True)
    load_latency = max(1, round((time.perf_counter() - load_started) * 1000))
    plan_by_key = {(call.configuration_id, call.fixture_id, call.model_field): call for call in plan}
    generated_by_config: dict[str, list[dict[str, Any]]] = {config.configuration_id: [] for config in CONFIGURATIONS}
    receipts: list[dict[str, Any]] = []
    for config in CONFIGURATIONS:
        for fixture in inputs.fixtures:
            preparation = prepared[(config.configuration_id, fixture.fixture_id)]
            generated: dict[str, dict[str, Any]] = {}
            for field in config.invoked_model_fields:
                call = plan_by_key[(config.configuration_id, fixture.fixture_id, field)]
                generated[field] = generate_one(
                    model=model, processor=processor, stream_generate=stream_generate,
                    apply_chat_template=apply_chat_template, mx=mx, preparation=preparation,
                    field=field, global_ordinal=call.global_ordinal, fixture_call_ordinal=call.fixture_call_ordinal,
                )
            model_evidence = write_model_evidence(
                fixture=fixture, config=config, preparation=preparation,
                generated=generated, output=output / config.label / fixture.fixture_id,
            )
            parser_receipt = shared_parse_subset(
                generated, output / config.label / fixture.fixture_id, arguments.swift_bin, repo_root
            )
            record, fixture_receipts = fixture_record(fixture, config, preparation, generated, parser_receipt)
            for receipt in fixture_receipts:
                receipt["model_evidence_artifact_sha256"] = model_evidence["artifact_sha256"]
            generated_by_config[config.configuration_id].append(record)
            receipts.extend(fixture_receipts)

    require(len(receipts) == MAX_CAMPAIGN_CALLS, "campaign did not emit exactly 280 generation receipts")
    require([row["global_ordinal"] for row in receipts] == list(range(1, MAX_CAMPAIGN_CALLS + 1)), "generation receipt ordinals drifted")
    run_records: list[dict[str, Any]] = []
    for config in CONFIGURATIONS:
        first_preparation = prepared[(config.configuration_id, inputs.fixtures[0].fixture_id)]
        record = run_record(
            inputs=inputs, config=config, preparation=first_preparation,
            fixtures=generated_by_config[config.configuration_id], model_safetensors_sha256=snapshot_sha,
            plan_sha256=plan_value["artifact_sha256"],
        )
        path = output / f"run-{config.label}.json"
        write_json(path, record)
        require(load_json(path).get("artifact_sha256") == artifact_sha256(load_json(path)), f"sealed run record mismatch: {path}")
        run_records.append({
            "configuration_id": config.configuration_id,
            "run_record_path": path.name,
            "run_record_sha256": sha256_path(path),
            "run_artifact_sha256": record["artifact_sha256"],
            "preparation_scope": config.preparation_scope,
        })
    campaign = {
        "schema": CAMPAIGN_SCHEMA,
        "route": ROUTE,
        "qualification": QUALIFICATION,
        "dataset_id": inputs.dataset_id,
        "admission_manifest_sha256": inputs.admission["artifact_sha256"],
        "evaluation_labels_sha256": inputs.labels["artifact_sha256"],
        "plan_sha256": plan_value["artifact_sha256"],
        "model": {"id": MODEL_ID, "revision": MODEL_REVISION, "snapshot_safetensors_sha256": snapshot_sha},
        "model_load_count": 1,
        "model_load_latency_milliseconds": load_latency,
        "generation_count": MAX_CAMPAIGN_CALLS,
        "snapshot_verification_sha256": verification_sha,
        "tool_source_sha256": source_hashes(repo_root),
        "runtime": runtime_versions(),
        "run_records": run_records,
        "global_generation_receipts": receipts,
    }
    campaign = seal_artifact(campaign)
    campaign_path = output / "campaign-receipt.json"
    write_json(campaign_path, campaign)
    require(load_json(campaign_path).get("artifact_sha256") == artifact_sha256(load_json(campaign_path)), "campaign output hash mismatch")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--model-root", required=True, type=Path, help="parent containing snapshot/ and VerifyModelSnapshot.py")
    result.add_argument("--blind-input", required=True, type=Path, help="sealed evaluator blind-input artifact for admission validation")
    result.add_argument("--blind-review", required=True, type=Path, help="sealed independent blind-review artifact for admission validation")
    result.add_argument("--admission-manifest", required=True, type=Path)
    result.add_argument("--evaluation-labels", required=True, type=Path)
    result.add_argument("--fixture-root", required=True, type=Path, help="directory containing exactly opaque <fixture_id>.png DEV inputs")
    result.add_argument("--output-dir", required=True, type=Path)
    result.add_argument("--swift-bin", default="swift")
    return result


def main() -> int:
    return execute(parser().parse_args())


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"FAILED subprocess: {error.cmd} exit={error.returncode}", file=sys.stderr)
        raise SystemExit(error.returncode)
    except (ContractFailure, OSError, ValueError) as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(2)
