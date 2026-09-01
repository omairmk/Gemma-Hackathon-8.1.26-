#!/usr/bin/python3
"""Fail-closed host gate for the single full-prefill 140/280 comparison.

This fresh lane consumes exactly one complete marker transcript for each arm.
It does not install, launch, retry, repair, or invoke Gemma. The device-side
harness emits one marker per frozen fixture; an operator runs both arms once,
then this gate validates the immutable pair and writes one decision receipt.
Semantic failure in either transcript is recorded but never prevents the other
complete transcript from being evaluated. Contract/infrastructure corruption
is the only host-gate error.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import math
import os
import pathlib
import re
import sys
from collections import Counter
from typing import Any


LANE = "GI_V1_PHOTO_FULL_PREFILL_NORMALIZATION_AB_V1"
FAMILY = "gi-v1-photo-full-prefill-normalization-policy-ab-v1"
MARKER_CONTRACT = "gi-v1-full-prefill-normalization-marker-v1"
PREFIX = "GI_V1_FULL_PREFILL_NORMALIZATION_AB_"
MODEL = "litert-gemma-4-e4b-28299f30"
MODEL_SHA256 = "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
PROMPT = "gi-photo-v1.4-full-prefill-v1"
PROMPT_SHA256 = "1b378173075b55724f3c68652b1561bfddcc2cdf75cd99360d4d53933edba583"
SCHEMA = "gi-photo-full-prefill-v1"
SCHEMA_SHA256 = "c44b50a1bf7b62b4b04cf2047036af8559b7f87168da83b755bd557519660533"
NORMALIZATION_POLICY = "gi-photo-dependent-field-abstention-v1"
QUALITY_POLICY = "gi-v1-extreme-photo-quality-v1"
MANIFEST_SHA256 = "00d8e8bc11b8ba83d4cb624bc69e45542b7aae0420a45b17d66e52232d34e7bc"
SOURCE_MANIFEST_SHA256 = "7412c39492b6b9031b4768d1b94722861be346fb36841a1e527dcc6da9c41f20"
MAX_INFERENCE_MS = 30_000
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclasses.dataclass(frozen=True)
class Fixture:
    fixture_id: str
    sha256: str
    screen: str
    bristol: int | None = None
    form: str | None = None
    mixed: str | None = None
    red: str | None = None
    black: str | None = None


FIXTURES = (
    Fixture("t12-type4-cold-start", "023ca013c9ce4eddbc6cb12a6647c5c14e3f5ad1255c8919a3ca5f4161deb3bc", "record_only_morphology_proxy", 4, "smooth_formed", "no", "no", "no"),
    Fixture("t08-brown-wood-block", "1f13896180c5b3f3f4fcc9cd2c632c2eb5349d490dc7f8141b6fc3f68b4d32ed", "non_stool"),
    Fixture("t09-red-capsule", "acf3e57b8236eab4a88de33d34aa2961f2ca25e18f9774e9788b17ea61cd54cc", "non_stool"),
    Fixture("t10-patterned-rug", "430d359f20988c60a947a9de7f42d45679100f78bbc4976f4499704764b09fe0", "non_stool"),
    Fixture("t11-green-smooth-prop", "0eadcccc35f56b0b9bdd7f1bb092267ab9b4fc2b0c67a7f8f2080c34b9dd0a14", "non_stool"),
    Fixture("t06-severe-darkness", "5baa425c2afac1ca3ebda872f74a0c47cf1580afcdb3435017bf2586ed85055b", "technical_too_dark"),
    Fixture("t07-severe-glare", "c663e73094172a742f981b24f0e9e03ba748e11ac4ceceade80555ca2cac151a", "technical_glare"),
    Fixture("t05-mixed-hard-loose", "f04cf1524eeb87d90055b954a3a4e047965c24f5f5b9769abcb711d3a68efc23", "no_forced_single_form", None, "mixed", "yes", "no", "no"),
    Fixture("t01-type1-brown-lumps", "e83ba8778ea30d947cca0802dc22342547c001961d6d19b5bb82b3d8d07cd05e", "record_only_morphology_proxy", 1, "hard_lumps", "no", "no", "no"),
    Fixture("t02-type3-cracked-formed", "7ab0aef66c9dd7e1723a17271be858c0b762ab9c32795c3b1473fd19e28ef116", "record_only_morphology_proxy", 3, "cracked_formed", "no", "no", "no"),
    Fixture("t03-type5-soft-blobs", "984910bae71e8753d9904ee20e46fa7e00719bafc83278ce45fd06e84a2e4403", "record_only_morphology_proxy", 5, "soft_blobs", "no", "no", "no"),
    Fixture("t04-type7-watery-pool", "769a6ef45f1b7cfc641d59f3a91e32b731b4442fe350ed76a348ae931b309949", "record_only_morphology_proxy", 7, "watery", "no", "no", "no"),
)

MARKER_KEYS = (
    "lane", "comparison_family", "marker_contract", "arm", "fixture",
    "fixture_sha256", "screen", "model", "model_sha256", "config", "prompt",
    "prompt_sha256", "schema", "schema_key_count", "schema_sha256",
    "normalization_policy", "quality_policy", "quality_gate", "context_tokens",
    "visual_tokens", "transport", "manifest_sha256", "source_manifest_sha256",
    "partition", "holdout_manifest_access", "holdout_asset_access",
    "journal_container", "isolation_attested", "strict_schema", "repair_used",
    "model_call_count", "expectation_scored", "expectation_pass",
    "inference_latency_ms", "end_to_end_latency_ms", "peak_rss_bytes",
    "output_kind", "output_sha256", "raw_response_sha256",
    "normalization_occurred", "normalization_count", "normalized_fields",
    "normalized_canonical_sha256", "raw_cross_field_contradiction",
    "image_usable", "retake_reason", "stool_presence", "bristol_type", "form",
    "mixed_form", "apparent_color", "red_appearing_material",
    "black_tarry_appearance", "subject_technical_pass", "bristol_within_one",
    "bristol_exact", "form_exact", "mixed_exact", "full_abstention",
    "semantic_points", "semantic_max_points", "error",
)

ARM_CONFIG = {
    "arm140": (140, "gi-v1-photo-full-prefill-normalization-v1-vt140"),
    "arm280": (280, "gi-v1-photo-full-prefill-normalization-v1-vt280"),
}
ABSTENTION = {
    "bristol_type": "null", "form": "unable_to_assess",
    "mixed_form": "not_sure", "apparent_color": "null",
    "red_appearing_material": "not_sure", "black_tarry_appearance": "not_sure",
}
ALLOWED_NORMALIZED_FIELDS = {
    "bristol_type", "form", "mixed_form", "apparent_color",
    "red_appearing_material", "black_tarry_appearance",
}
FORMS = {
    "hard_lumps", "lumpy_formed", "cracked_formed", "smooth_formed",
    "soft_blobs", "mushy", "watery", "mixed", "unable_to_assess",
}
BRISTOL_FORMS = {
    1: "hard_lumps", 2: "lumpy_formed", 3: "cracked_formed",
    4: "smooth_formed", 5: "soft_blobs", 6: "mushy", 7: "watery",
}
COLORS = {
    "null", "brown", "light_brown", "dark_brown", "green", "yellow",
    "orange", "red_appearing", "black_appearing", "pale_or_clay_appearing",
    "mixed",
}


class ContractError(ValueError):
    pass


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_marker(line: str) -> tuple[str, dict[str, str]]:
    pieces = line.strip().split()
    if not pieces or pieces[0] not in {PREFIX + "PASS", PREFIX + "FAIL"}:
        raise ContractError("invalid terminal prefix")
    values: dict[str, str] = {}
    ordered: list[str] = []
    for token in pieces[1:]:
        if token.count("=") != 1:
            raise ContractError("marker token is not one key/value pair")
        key, value = token.split("=", 1)
        if not key or not value or key in values:
            raise ContractError("empty or duplicate marker field")
        values[key] = value
        ordered.append(key)
    if tuple(ordered) != MARKER_KEYS:
        raise ContractError("marker keys/order differ from fresh contract")
    return pieces[0][len(PREFIX):], values


def require(values: dict[str, str], key: str, expected: str) -> None:
    if values[key] != expected:
        raise ContractError(f"{key} expected {expected}, got {values[key]}")


def integer(values: dict[str, str], key: str, minimum: int = 0) -> int:
    try:
        value = int(values[key])
    except ValueError as error:
        raise ContractError(f"{key} is not an integer") from error
    if value < minimum:
        raise ContractError(f"{key} is below {minimum}")
    return value


def is_abstention(values: dict[str, str]) -> bool:
    return all(values[key] == expected for key, expected in ABSTENTION.items())


def semantic_assessment(
    values: dict[str, str], fixture: Fixture,
) -> dict[str, bool | None]:
    full_abstention = is_abstention(values)
    if fixture.screen == "record_only_morphology_proxy":
        subject = (
            values["image_usable"] == "true"
            and values["retake_reason"] == "null"
            and values["stool_presence"] == "stool"
        )
    elif fixture.screen == "no_forced_single_form":
        subject = (
            values["image_usable"] == "true"
            and values["retake_reason"] == "null"
            and values["stool_presence"] == "stool"
            and values["bristol_type"] == "null"
            and values["form"] == "mixed"
            and values["mixed_form"] == "yes"
        )
    elif fixture.screen == "technical_too_dark":
        subject = (
            values["image_usable"] == "false"
            and values["retake_reason"] == "too_dark"
            and values["stool_presence"] == "uncertain"
            and full_abstention
        )
    elif fixture.screen == "technical_glare":
        subject = (
            values["image_usable"] == "false"
            and values["retake_reason"] == "glare"
            and values["stool_presence"] == "uncertain"
            and full_abstention
        )
    elif fixture.screen == "non_stool":
        subject = (
            values["image_usable"] == "true"
            and values["retake_reason"] == "null"
            and values["stool_presence"] in {"non_stool", "uncertain"}
            and full_abstention
        )
    else:  # Frozen screens are closed above; fail closed if the table drifts.
        raise ContractError(f"unsupported frozen screen {fixture.screen}")

    observed_bristol = (
        None if values["bristol_type"] == "null"
        else int(values["bristol_type"])
    )
    return {
        "subject_technical_pass": subject,
        "bristol_within_one": (
            None if fixture.bristol is None
            else observed_bristol is not None
            and abs(observed_bristol - fixture.bristol) <= 1
        ),
        "bristol_exact": (
            None if fixture.bristol is None
            else observed_bristol == fixture.bristol
        ),
        "form_exact": (
            None if fixture.form is None else values["form"] == fixture.form
        ),
        "mixed_exact": (
            None if fixture.mixed is None
            else values["mixed_form"] == fixture.mixed
        ),
        "full_abstention": (
            full_abstention if fixture.screen in {
                "non_stool", "technical_too_dark", "technical_glare",
            } else None
        ),
    }


def semantic_marker_fields(
    assessment: dict[str, bool | None],
) -> dict[str, str]:
    def token(value: bool | None) -> str:
        if value is None:
            return "not_scored"
        return "true" if value else "false"

    scored = list(assessment.values())
    points = sum(value is True for value in scored)
    maximum = sum(value is not None for value in scored)
    fields = {key: token(value) for key, value in assessment.items()}
    fields["semantic_points"] = str(points)
    fields["semantic_max_points"] = str(maximum)
    return fields


def validate_primitive_tuple(values: dict[str, str]) -> None:
    if values["image_usable"] not in {"true", "false"}:
        raise ContractError("invalid image_usable")
    if values["retake_reason"] not in {
        "null", "too_dark", "blurred", "obstructed", "too_far", "glare", "other",
    }:
        raise ContractError("invalid retake_reason")
    if values["stool_presence"] not in {"stool", "non_stool", "uncertain"}:
        raise ContractError("invalid stool_presence")
    if values["bristol_type"] not in {"null", "1", "2", "3", "4", "5", "6", "7"}:
        raise ContractError("invalid bristol_type")
    if values["form"] not in FORMS or values["apparent_color"] not in COLORS:
        raise ContractError("invalid form or color")
    for key in ("mixed_form", "red_appearing_material", "black_tarry_appearance"):
        if values[key] not in {"yes", "no", "not_sure"}:
            raise ContractError(f"invalid {key}")
    if values["image_usable"] == "false":
        if values["retake_reason"] == "null" or values["stool_presence"] != "uncertain" or not is_abstention(values):
            raise ContractError("unusable tuple is not a technical abstention")
    elif values["retake_reason"] != "null":
        raise ContractError("usable tuple has retake reason")
    elif values["stool_presence"] != "stool":
        if not is_abstention(values):
            raise ContractError("usable non-stool/uncertain tuple did not abstain")
    elif values["mixed_form"] == "no":
        if values["bristol_type"] == "null":
            raise ContractError("usable single-form stool omitted Bristol")
        if values["form"] != BRISTOL_FORMS[int(values["bristol_type"])]:
            raise ContractError("usable single-form stool Bristol/form mismatch")
    elif values["mixed_form"] == "yes":
        if values["bristol_type"] != "null" or values["form"] != "mixed":
            raise ContractError("mixed stool tuple is inconsistent")
    elif values["bristol_type"] != "null" or values["form"] != "unable_to_assess":
        raise ContractError("not-sure stool tuple is inconsistent")


def validate_marker(
    outcome: str,
    values: dict[str, str],
    arm: str,
    fixture: Fixture,
) -> list[str]:
    budget, config = ARM_CONFIG[arm]
    exact = {
        "lane": LANE, "comparison_family": FAMILY, "marker_contract": MARKER_CONTRACT,
        "arm": arm, "fixture": fixture.fixture_id, "fixture_sha256": fixture.sha256,
        "screen": fixture.screen, "model": MODEL, "model_sha256": MODEL_SHA256,
        "config": config, "prompt": PROMPT, "prompt_sha256": PROMPT_SHA256,
        "schema": SCHEMA, "schema_key_count": "10", "schema_sha256": SCHEMA_SHA256,
        "normalization_policy": NORMALIZATION_POLICY, "quality_policy": QUALITY_POLICY,
        "context_tokens": "1536", "visual_tokens": str(budget),
        "transport": "validated_sanitized_jpeg_image_data",
        "manifest_sha256": MANIFEST_SHA256,
        "source_manifest_sha256": SOURCE_MANIFEST_SHA256, "partition": "tuning",
        "holdout_manifest_access": "false", "holdout_asset_access": "false",
        "journal_container": "ephemeral", "isolation_attested": "true",
        "repair_used": "false",
    }
    for key, expected in exact.items():
        require(values, key, expected)
    end_to_end = integer(values, "end_to_end_latency_ms", 0)
    rss = integer(values, "peak_rss_bytes", 1)
    del rss
    if values["error"] == "inference_deadline_exceeded" and (
        values["strict_schema"] == "false"
        and values["output_kind"] == "unavailable"
    ):
        if outcome != "FAIL" or fixture.screen.startswith("technical_"):
            raise ContractError("timeout marker is not a model-arm failure")
        for key in (
            "output_sha256", "raw_response_sha256", "normalization_occurred",
            "normalization_count", "normalized_fields",
            "normalized_canonical_sha256", "raw_cross_field_contradiction",
            "image_usable", "retake_reason", "stool_presence", "bristol_type",
            "form", "mixed_form", "apparent_color", "red_appearing_material",
            "black_tarry_appearance", "subject_technical_pass",
            "bristol_within_one", "bristol_exact", "form_exact", "mixed_exact",
            "full_abstention",
        ):
            require(values, key, "unavailable")
        require(values, "quality_gate", "unavailable")
        require(values, "model_call_count", "-1")
        require(values, "expectation_scored", "false")
        require(values, "expectation_pass", "not_scored")
        require(values, "inference_latency_ms", "-1")
        require(values, "semantic_points", "-1")
        require(values, "semantic_max_points", "-1")
        return [f"{fixture.fixture_id}:inference_deadline"]
    if values["output_sha256"] != values["raw_response_sha256"]:
        raise ContractError("raw response hash aliases disagree")
    if not SHA256_RE.fullmatch(values["raw_response_sha256"]):
        raise ContractError("invalid raw response hash")
    semantic_errors: list[str] = []
    technical_reason = {
        "technical_too_dark": "too_dark", "technical_glare": "glare",
    }.get(fixture.screen)
    calls = integer(values, "model_call_count", 0)
    inference = integer(values, "inference_latency_ms", 0)
    if end_to_end < inference:
        raise ContractError("end-to-end latency precedes inference latency")
    if technical_reason:
        if calls != 0 or inference != 0 or values["quality_gate"] != technical_reason:
            semantic_errors.append(f"{fixture.fixture_id}:deterministic_quality_gate")
    else:
        if calls != 1 or values["quality_gate"] != "passed_to_gemma":
            semantic_errors.append(f"{fixture.fixture_id}:model_call_count")
        if not (1 <= inference <= MAX_INFERENCE_MS):
            semantic_errors.append(f"{fixture.fixture_id}:inference_deadline")

    strict = values["strict_schema"] == "true"
    if values["strict_schema"] not in {"true", "false"}:
        raise ContractError("invalid strict_schema flag")
    if not strict:
        if outcome != "FAIL" or values["output_kind"] != "raw_response_sha256_only":
            raise ContractError("schema failure was not explicit fail-closed")
        for key in (
            "normalization_occurred", "normalization_count", "normalized_fields",
            "normalized_canonical_sha256",
            "image_usable", "retake_reason", "stool_presence", "bristol_type", "form",
            "mixed_form", "apparent_color", "red_appearing_material",
            "black_tarry_appearance",
        ):
            require(values, key, "unavailable")
        if values["error"] == "strict_schema_inconsistent":
            require(values, "raw_cross_field_contradiction", "true")
        else:
            require(values, "raw_cross_field_contradiction", "unavailable")
        require(values, "expectation_scored", "false")
        require(values, "expectation_pass", "not_scored")
        for key in (
            "subject_technical_pass", "bristol_within_one", "bristol_exact",
            "form_exact", "mixed_exact", "full_abstention",
        ):
            require(values, key, "unavailable")
        require(values, "semantic_points", "-1")
        require(values, "semantic_max_points", "-1")
        semantic_errors.append(f"{fixture.fixture_id}:strict_schema")
        return semantic_errors

    if values["output_kind"] != "canonical_strict_json":
        raise ContractError("strict output kind mismatch")
    if not SHA256_RE.fullmatch(values["normalized_canonical_sha256"]):
        raise ContractError("invalid normalized canonical hash")
    validate_primitive_tuple(values)
    occurred = values["normalization_occurred"]
    contradiction = values["raw_cross_field_contradiction"]
    if occurred not in {"true", "false"} or contradiction not in {"true", "false"}:
        raise ContractError("invalid normalization flags")
    if occurred == "true" and contradiction != "true":
        raise ContractError("normalization lacks a raw contradiction receipt")
    require(values, "normalization_count", "1" if occurred == "true" else "0")
    if occurred == "true":
        changed = set(values["normalized_fields"].split("."))
        if not changed or not changed.issubset(ALLOWED_NORMALIZED_FIELDS):
            raise ContractError("invalid normalized field receipt")
    else:
        require(values, "normalized_fields", "none")

    assessment = semantic_assessment(values, fixture)
    for key, expected in semantic_marker_fields(assessment).items():
        require(values, key, expected)
    require(values, "expectation_scored", "true")
    require(
        values,
        "expectation_pass",
        "true" if assessment["subject_technical_pass"] else "false",
    )
    if technical_reason:
        if values["image_usable"] != "false" or values["retake_reason"] != technical_reason or not is_abstention(values):
            semantic_errors.append(f"{fixture.fixture_id}:technical_abstention")

    if fixture.screen == "non_stool":
        if values["image_usable"] != "true" or values["stool_presence"] not in {"non_stool", "uncertain"} or not is_abstention(values):
            semantic_errors.append(f"{fixture.fixture_id}:nonstool_abstention")
    elif fixture.screen == "no_forced_single_form":
        if values["stool_presence"] != "stool" or values["bristol_type"] != "null" or values["form"] != "mixed" or values["mixed_form"] != "yes":
            semantic_errors.append(f"{fixture.fixture_id}:mixed_form")
    elif fixture.screen == "record_only_morphology_proxy":
        if values["image_usable"] != "true" or values["stool_presence"] != "stool":
            semantic_errors.append(f"{fixture.fixture_id}:clear_stool_subject")
    if outcome == "FAIL" and not semantic_errors:
        semantic_errors.append(f"{fixture.fixture_id}:{values['error']}")
    return semantic_errors


def read_arm(path: pathlib.Path, arm: str) -> tuple[list[dict[str, str]], list[str]]:
    if not path.is_file() or path.is_symlink():
        raise ContractError(f"unsafe or missing marker file: {path}")
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(lines) != len(FIXTURES):
        raise ContractError(f"{arm} must contain exactly {len(FIXTURES)} markers")
    parsed: list[dict[str, str]] = []
    errors: list[str] = []
    for line, fixture in zip(lines, FIXTURES):
        outcome, values = parse_marker(line)
        errors.extend(validate_marker(outcome, values, arm, fixture))
        parsed.append(values)
    return parsed, errors


def summarize(markers: list[dict[str, str]], errors: list[str]) -> dict[str, Any]:
    strict_markers = [marker for marker in markers if marker["strict_schema"] == "true"]
    assessed = [
        semantic_assessment(marker, fixture)
        if marker["strict_schema"] == "true" else None
        for marker, fixture in zip(markers, FIXTURES)
    ]
    stool = [
        (marker, assessment)
        for marker, fixture, assessment in zip(markers, FIXTURES, assessed)
        if fixture.bristol is not None
    ]
    within = sum(
        assessment is not None and assessment["bristol_within_one"] is True
        for _, assessment in stool
    )
    exact = sum(
        assessment is not None and assessment["bristol_exact"] is True
        for _, assessment in stool
    )
    if len(stool) != 5:
        raise ContractError("frozen Bristol denominator drift")
    if within < math.ceil(0.80 * len(stool)):
        errors.append("arm:bristol_within_one_below_80_percent")
    if exact < math.ceil(0.55 * len(stool)):
        errors.append("arm:bristol_exact_below_55_percent")
    predicted_types = {
        marker["bristol_type"] for marker, assessment in stool
        if assessment is not None
    }
    predicted_forms = {
        marker["form"] for marker, assessment in stool
        if assessment is not None
    }
    if len(predicted_types) < 3 or len(predicted_forms) < 3:
        errors.append("arm:repeated_default_output_collapse")
    model_called_hashes = [
        marker["raw_response_sha256"] for marker in markers
        if marker["model_call_count"] == "1"
    ]
    if model_called_hashes and max(Counter(model_called_hashes).values()) >= 5:
        errors.append("arm:raw_output_hash_collapse")

    declared_red_black: list[bool] = []
    semantic_vector: dict[str, bool] = {}
    for marker, fixture, assessment in zip(markers, FIXTURES, assessed):
        if fixture.bristol is not None:
            semantic_vector[f"{fixture.fixture_id}:bristol_within_one"] = (
                assessment is not None
                and assessment["bristol_within_one"] is True
            )
            semantic_vector[f"{fixture.fixture_id}:bristol_exact"] = (
                assessment is not None and assessment["bristol_exact"] is True
            )
        if fixture.form is not None:
            semantic_vector[f"{fixture.fixture_id}:form"] = (
                assessment is not None and marker["form"] == fixture.form
            )
        if fixture.mixed is not None:
            semantic_vector[f"{fixture.fixture_id}:mixed"] = (
                assessment is not None and marker["mixed_form"] == fixture.mixed
            )
        if fixture.red is not None:
            result = (
                assessment is not None
                and marker["red_appearing_material"] == fixture.red
            )
            declared_red_black.append(result)
            semantic_vector[f"{fixture.fixture_id}:red"] = result
        if fixture.black is not None:
            result = (
                assessment is not None
                and marker["black_tarry_appearance"] == fixture.black
            )
            declared_red_black.append(result)
            semantic_vector[f"{fixture.fixture_id}:black"] = result
        semantic_vector[f"{fixture.fixture_id}:subject_technical"] = (
            assessment is not None
            and assessment["subject_technical_pass"] is True
        )
    return {
        "passed": not errors,
        "errors": sorted(set(errors)),
        "strict_schema_valid": len(strict_markers),
        "strict_schema_fail_closed": len(markers) - len(strict_markers),
        "raw_cross_field_contradictions": sum(
            marker["raw_cross_field_contradiction"] == "true" for marker in markers
        ),
        "strict_cross_field_failures": sum(
            marker["strict_schema"] == "false"
            and marker["error"] == "strict_schema_inconsistent"
            for marker in markers
        ),
        "normalizations": sum(
            marker["normalization_occurred"] == "true" for marker in strict_markers
        ),
        "bristol_denominator": len(stool),
        "bristol_within_one": within,
        "bristol_exact": exact,
        "predeclared_red_black_denominator": len(declared_red_black),
        "predeclared_red_black_exact": sum(declared_red_black),
        "distinct_clear_stool_bristol_outputs": len(predicted_types),
        "distinct_clear_stool_form_outputs": len(predicted_forms),
        "maximum_inference_latency_ms": max(
            int(marker["inference_latency_ms"])
            for marker in markers if marker["inference_latency_ms"] != "-1"
        ),
        "maximum_peak_rss_bytes": max(int(marker["peak_rss_bytes"]) for marker in markers),
        "semantic_vector": semantic_vector,
    }


def validate_cross_arm(markers140: list[dict[str, str]], markers280: list[dict[str, str]]) -> None:
    allowed_differences = {
        "arm", "config", "visual_tokens", "quality_gate", "strict_schema",
        "model_call_count", "expectation_scored", "expectation_pass",
        "inference_latency_ms",
        "end_to_end_latency_ms", "peak_rss_bytes", "output_kind", "output_sha256",
        "raw_response_sha256", "normalization_occurred", "normalization_count",
        "normalized_fields", "normalized_canonical_sha256", "raw_cross_field_contradiction",
        "image_usable", "retake_reason", "stool_presence", "bristol_type", "form",
        "mixed_form", "apparent_color", "red_appearing_material",
        "black_tarry_appearance", "subject_technical_pass", "bristol_within_one",
        "bristol_exact", "form_exact", "mixed_exact", "full_abstention",
        "semantic_points", "semantic_max_points", "error",
    }
    for left, right in zip(markers140, markers280):
        for key in MARKER_KEYS:
            if key not in allowed_differences and left[key] != right[key]:
                raise ContractError(f"arms differ in frozen field {key}")


def decide(summary140: dict[str, Any], summary280: dict[str, Any]) -> dict[str, Any]:
    pass140, pass280 = summary140["passed"], summary280["passed"]
    vector140 = summary140["semantic_vector"]
    vector280 = summary280["semantic_vector"]
    fixed = sorted(key for key in vector140 if not vector140[key] and vector280[key])
    regressions = sorted(key for key in vector140 if vector140[key] and not vector280[key])
    semantic_280_gain = (
        pass280 and len(fixed) >= 2 and not regressions
        and summary280["bristol_within_one"] >= summary140["bristol_within_one"]
        and summary280["bristol_exact"] >= summary140["bristol_exact"]
    )
    if pass140 and not pass280:
        selected, reason = 140, "only_140_passed"
    elif pass280 and not pass140:
        selected, reason = 280, "only_280_passed_physical_gate_open"
    elif pass140 and pass280 and semantic_280_gain:
        selected, reason = 140, "280_semantic_gain_requires_bound_physical_qualification"
    else:
        selected, reason = 140, "140_default_or_manual_fallback"
    return {
        "selected_visual_tokens": selected,
        "reason": reason,
        "promotion_qualified": False,
        "physical_gate_open": True,
        "manual_fallback_required": selected == 140 and not pass140,
        "280_fixed_semantic_errors": fixed,
        "280_semantic_regressions": regressions,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm-140-markers", type=pathlib.Path, required=True)
    parser.add_argument("--arm-280-markers", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    if args.output.exists() or args.output.is_symlink():
        raise ContractError("refusing to overwrite comparison receipt")
    markers140, errors140 = read_arm(args.arm_140_markers, "arm140")
    markers280, errors280 = read_arm(args.arm_280_markers, "arm280")
    validate_cross_arm(markers140, markers280)
    summary140 = summarize(markers140, errors140)
    summary280 = summarize(markers280, errors280)
    receipt = {
        "schema_version": "gi-v1-full-prefill-normalization-ab-decision-v1",
        "lane": LANE,
        "normalization_policy": NORMALIZATION_POLICY,
        "arm140_markers_sha256": sha256_file(args.arm_140_markers),
        "arm280_markers_sha256": sha256_file(args.arm_280_markers),
        "arm140": summary140,
        "arm280": summary280,
        "decision": decide(summary140, summary280),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + f".tmp.{os.getpid()}")
    try:
        with temporary.open("x", encoding="utf-8") as handle:
            json.dump(receipt, handle, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, args.output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ContractError, json.JSONDecodeError, OSError) as error:
        print(f"FULL_PREFILL_NORMALIZATION_AB_CONTRACT_ERROR: {error}", file=sys.stderr)
        raise SystemExit(65)
