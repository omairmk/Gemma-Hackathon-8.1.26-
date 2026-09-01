#!/usr/bin/python3
"""Validate requested/effective Qwen QA resolution evidence.

The physical runner performs the full seven-field/request validator separately.
This focused validator binds the requested profile to the exact sanitized source,
square derivative, processor frame, hashes, latency, memory and thermal receipt.
It can also replay historical v1 256/512 preprocess events without interpreting
them as current evidence.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


CURRENT_SCHEMA = "qwen3-decomposed-physical-evidence-v2"
HISTORICAL_SCHEMA = "qwen3-decomposed-physical-evidence-v1"
SHA256 = re.compile(r"[0-9a-f]{64}")
THERMAL_STATES = {"nominal", "fair", "serious", "critical", "unknown"}


class ResolutionEvidenceError(ValueError):
    pass


@dataclass(frozen=True)
class ProfileContract:
    profile: str
    preprocessing_version: str
    derivative_edge: int
    pixel_budget: int
    frame_edge: int
    post_merge_visual_tokens: int
    semantically_admitted: bool


PROFILE_CONTRACTS = {
    "1024": ProfileContract(
        "1024", "qwen3vl-hybrid-1024-qa-v1", 1024, 1_048_576, 64, 1_024, True
    ),
    "512": ProfileContract(
        "512", "qwen3vl-hybrid-512-v2-preprocessing-evidence", 512, 262_144, 32, 256, True
    ),
    "256": ProfileContract(
        "256",
        "qwen3vl-hybrid-256-qa-resource-fallback-v2-preprocessing-evidence",
        512,
        65_536,
        16,
        64,
        False,
    ),
}


def fail(message: str) -> "NoReturn":
    raise ResolutionEvidenceError(message)


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and SHA256.fullmatch(value) is not None


def positive_int(record: dict[str, Any], field: str) -> int:
    value = record.get(field)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        fail(f"{field} must be a positive integer")
    return value


def nonnegative_int(record: dict[str, Any], field: str) -> int:
    value = record.get(field)
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        fail(f"{field} must be a nonnegative integer")
    return value


def validate_historical_preprocess(
    start: dict[str, Any], preprocess: dict[str, Any], contract: ProfileContract
) -> None:
    if contract.profile == "1024":
        fail("historical schema never established a 1024 profile")
    if preprocess.get("frameT") != 1:
        fail("historical frameT must be 1")
    if preprocess.get("frameH") != contract.frame_edge or preprocess.get("frameW") != contract.frame_edge:
        fail("historical processor frame does not match its declared profile")
    if preprocess.get("analyzedImageSHA256") != start.get("analyzedImageSHA256"):
        fail("historical source hash binding is invalid")
    if not is_sha256(preprocess.get("preparedTensorSHA256")):
        fail("historical tensor hash is invalid")


def validate_current_preprocess(
    start: dict[str, Any], preprocess: dict[str, Any], contract: ProfileContract
) -> None:
    for record, label in ((start, "request_started"), (preprocess, "preprocess_completed")):
        if record.get("profile") != contract.profile:
            fail(f"{label} profile does not match the requested profile")
        if record.get("requestedProfile") != contract.profile:
            fail(f"{label} requestedProfile is invalid")
        if record.get("effectiveProfile") != contract.profile:
            fail(f"{label} effectiveProfile must equal requestedProfile; no hidden fallback is allowed")
        if record.get("preprocessingVersion") != contract.preprocessing_version:
            fail(f"{label} preprocessingVersion is invalid")
        if record.get("pixelBudget") != contract.pixel_budget:
            fail(f"{label} pixelBudget is invalid")
        if record.get("expectedFrameT") != 1:
            fail(f"{label} expectedFrameT must be 1")
        if record.get("expectedFrameH") != contract.frame_edge or record.get("expectedFrameW") != contract.frame_edge:
            fail(f"{label} expected processor frame is invalid")
        if record.get("postMergeVisualTokenCount") != contract.post_merge_visual_tokens:
            fail(f"{label} post-merge visual token count is invalid")

    source_width = positive_int(start, "sourcePixelWidth")
    source_height = positive_int(start, "sourcePixelHeight")
    if start.get("analyzedPixelWidth") != source_width or start.get("analyzedPixelHeight") != source_height:
        fail("request_started analyzed/source dimensions disagree")
    if start.get("derivativePixelWidth") != contract.derivative_edge:
        fail("request_started derivative width is invalid")
    if start.get("derivativePixelHeight") != contract.derivative_edge:
        fail("request_started derivative height is invalid")
    source_sha = start.get("analyzedImageSHA256")
    if not is_sha256(source_sha):
        fail("request_started source hash is invalid")

    if preprocess.get("analyzedImageSHA256") != source_sha:
        fail("preprocess source hash does not match request_started")
    if positive_int(preprocess, "sourcePixelWidth") != source_width:
        fail("preprocess source width does not match request_started")
    if positive_int(preprocess, "sourcePixelHeight") != source_height:
        fail("preprocess source height does not match request_started")
    derivative_width = positive_int(preprocess, "derivativePixelWidth")
    derivative_height = positive_int(preprocess, "derivativePixelHeight")
    if derivative_width != contract.derivative_edge or derivative_height != contract.derivative_edge:
        fail("preprocess derivative dimensions are unsupported")
    content_width = positive_int(preprocess, "derivativeContentPixelWidth")
    content_height = positive_int(preprocess, "derivativeContentPixelHeight")
    if content_width > derivative_width or content_height > derivative_height:
        fail("derivative content exceeds the square derivative")
    deterministic_width = positive_int(preprocess, "deterministicDerivativePixelWidth")
    deterministic_height = positive_int(preprocess, "deterministicDerivativePixelHeight")
    if deterministic_width != 512 or deterministic_height != 512:
        fail("deterministic derivative dimensions must remain exactly 512x512")
    if not is_sha256(preprocess.get("deterministicDerivativeRGBASHA256")):
        fail("deterministic derivative RGBA hash is invalid")
    if preprocess.get("effectiveSourcePixelWidth") != min(source_width, content_width):
        fail("effective source width overclaims or understates real detail")
    if preprocess.get("effectiveSourcePixelHeight") != min(source_height, content_height):
        fail("effective source height overclaims or understates real detail")
    was_upscaled = content_width > source_width or content_height > source_height
    if preprocess.get("sourceWasUpscaled") is not was_upscaled:
        fail("sourceWasUpscaled is not truthful")
    if preprocess.get("frameT") != 1:
        fail("actual frameT must be 1")
    if preprocess.get("frameH") != contract.frame_edge or preprocess.get("frameW") != contract.frame_edge:
        fail("actual processor frame does not match the requested profile")
    if not is_sha256(preprocess.get("derivativeRGBASHA256")):
        fail("derivative RGBA hash is invalid")
    if not is_sha256(preprocess.get("preparedTensorSHA256")):
        fail("prepared tensor hash is invalid")
    nonnegative_int(preprocess, "preprocessLatencyMilliseconds")
    nonnegative_int(preprocess, "availableMemoryBytes")
    nonnegative_int(preprocess, "mlxActiveMemoryBytes")
    nonnegative_int(preprocess, "mlxPeakMemoryBytes")
    nonnegative_int(preprocess, "mlxCacheMemoryBytes")
    nonnegative_int(preprocess, "hostPeakRSSBytes")
    if preprocess.get("thermalState") not in THERMAL_STATES:
        fail("preprocess thermalState is invalid")


def validate_records(
    records: Iterable[dict[str, Any]],
    requested_profile: str,
    *,
    require_current_schema: bool,
) -> int:
    if requested_profile not in PROFILE_CONTRACTS:
        fail("requested profile must be exactly 1024, 512, or 256")
    contract = PROFILE_CONTRACTS[requested_profile]
    records = list(records)
    ready_indexes = [
        index
        for index, record in enumerate(records)
        if record.get("event") == "journal_ready" and record.get("profile") == requested_profile
    ]
    if not ready_indexes:
        fail("matching journal_ready event is missing")
    segment = records[ready_indexes[-1] :]
    segment_schema = segment[0].get("schemaVersion")
    if require_current_schema and segment_schema != CURRENT_SCHEMA:
        fail("the current runner requires v2 resolution evidence")
    if segment_schema not in {CURRENT_SCHEMA, HISTORICAL_SCHEMA}:
        fail("unsupported physical evidence schema")
    if any(record.get("schemaVersion") != segment_schema for record in segment):
        fail("one qualification segment cannot mix evidence schemas")

    starts = [record for record in segment if record.get("event") == "request_started"]
    if not starts:
        fail("request_started evidence is missing")
    seen_request_ids: set[str] = set()
    for start in starts:
        request_id = start.get("requestID")
        if not isinstance(request_id, str) or not request_id or request_id in seen_request_ids:
            fail("request_started IDs must be unique and nonempty")
        seen_request_ids.add(request_id)
        preprocesses = [
            record
            for record in segment
            if record.get("event") == "preprocess_completed" and record.get("requestID") == request_id
        ]
        if len(preprocesses) != 1:
            fail("each request requires exactly one preprocess_completed event")
        if segment_schema == HISTORICAL_SCHEMA:
            validate_historical_preprocess(start, preprocesses[0], contract)
        else:
            validate_current_preprocess(start, preprocesses[0], contract)
            if contract.semantically_admitted:
                completions = [
                    record
                    for record in segment
                    if record.get("event") == "request_completed"
                    and record.get("requestID") == request_id
                ]
                if len(completions) != 1:
                    fail("each admitted request requires exactly one request_completed event")
                completion = completions[0]
                if completion.get("profile") != contract.profile:
                    fail("request_completed profile does not match the requested profile")
                if completion.get("analyzedImageSHA256") != start.get("analyzedImageSHA256"):
                    fail("request_completed source hash does not match request_started")
                if completion.get("modelCallCount") != 7:
                    fail("request_completed must report exactly seven model calls")
                nonnegative_int(completion, "requestLatencyMilliseconds")
    if segment_schema == CURRENT_SCHEMA and contract.semantically_admitted:
        completed_ids = [
            record.get("requestID")
            for record in segment
            if record.get("event") == "request_completed"
        ]
        if len(completed_ids) != len(starts) or set(completed_ids) != seen_request_ids:
            fail("current admitted evidence must complete every started request exactly once")
    return len(starts)


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.endswith("\n"):
                fail(f"line {line_number} is not newline-terminated")
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                fail(f"line {line_number} is not valid JSON: {error}")
            if not isinstance(record, dict):
                fail(f"line {line_number} must contain a JSON object")
            records.append(record)
    return records


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "usage: ValidateQwen3ResolutionEvidence.py <physical-runs.jsonl> <1024|512|256>",
            file=sys.stderr,
        )
        return 2
    try:
        count = validate_records(
            load_jsonl(Path(argv[1])), argv[2], require_current_schema=True
        )
    except (OSError, ResolutionEvidenceError) as error:
        print(f"QWEN3_RESOLUTION_EVIDENCE: FAIL: {error}", file=sys.stderr)
        return 1
    print(
        f"QWEN3_RESOLUTION_EVIDENCE: PASS profile={argv[2]} requests={count} "
        "source_derivative_frame_hash_latency_memory_thermal_bound=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
