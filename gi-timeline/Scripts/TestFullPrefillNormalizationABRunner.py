#!/usr/bin/python3
"""Host-only tests for the fresh normalization-bound 140/280 lane."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
MODULE_PATH = ROOT / "RunFullPrefillNormalizationAB.py"
CONTROLLER = ROOT / "RunFullPrefillNormalizationABSimulator.sh"
HARNESS_SOURCE = ROOT.parent / "GITimeline" / "DeviceInferenceLab.swift"
PROJECT_SOURCE = ROOT.parent / "GITimeline.xcodeproj" / "project.pbxproj"
spec = importlib.util.spec_from_file_location("normalization_ab", MODULE_PATH)
assert spec and spec.loader
ab = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = ab
spec.loader.exec_module(ab)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def marker(arm: str, fixture: ab.Fixture, updates: dict[str, str] | None = None) -> str:
    budget, config = ab.ARM_CONFIG[arm]
    technical = {
        "technical_too_dark": "too_dark",
        "technical_glare": "glare",
    }.get(fixture.screen)
    if technical:
        values = {
            "image_usable": "false", "retake_reason": technical,
            "stool_presence": "uncertain", **ab.ABSTENTION,
        }
        calls, inference, quality = "0", "0", technical
    elif fixture.screen == "non_stool":
        values = {
            "image_usable": "true", "retake_reason": "null",
            "stool_presence": "non_stool", **ab.ABSTENTION,
        }
        calls, inference, quality = "1", "1000", "passed_to_gemma"
    elif fixture.screen == "no_forced_single_form":
        values = {
            "image_usable": "true", "retake_reason": "null",
            "stool_presence": "stool", "bristol_type": "null", "form": "mixed",
            "mixed_form": "yes", "apparent_color": "brown",
            "red_appearing_material": "no", "black_tarry_appearance": "no",
        }
        calls, inference, quality = "1", "1000", "passed_to_gemma"
    else:
        values = {
            "image_usable": "true", "retake_reason": "null",
            "stool_presence": "stool", "bristol_type": str(fixture.bristol),
            "form": str(fixture.form), "mixed_form": "no", "apparent_color": "brown",
            "red_appearing_material": "no", "black_tarry_appearance": "no",
        }
        calls, inference, quality = "1", "1000", "passed_to_gemma"

    raw_hash = digest(f"{arm}:{fixture.fixture_id}:{json.dumps(values, sort_keys=True)}")
    fields = {
        "lane": ab.LANE,
        "comparison_family": ab.FAMILY,
        "marker_contract": ab.MARKER_CONTRACT,
        "arm": arm,
        "fixture": fixture.fixture_id,
        "fixture_sha256": fixture.sha256,
        "screen": fixture.screen,
        "model": ab.MODEL,
        "model_sha256": ab.MODEL_SHA256,
        "config": config,
        "prompt": ab.PROMPT,
        "prompt_sha256": ab.PROMPT_SHA256,
        "schema": ab.SCHEMA,
        "schema_key_count": "10",
        "schema_sha256": ab.SCHEMA_SHA256,
        "normalization_policy": ab.NORMALIZATION_POLICY,
        "quality_policy": ab.QUALITY_POLICY,
        "quality_gate": quality,
        "context_tokens": "1536",
        "visual_tokens": str(budget),
        "transport": "validated_sanitized_jpeg_image_data",
        "manifest_sha256": ab.MANIFEST_SHA256,
        "source_manifest_sha256": ab.SOURCE_MANIFEST_SHA256,
        "partition": "tuning",
        "holdout_manifest_access": "false",
        "holdout_asset_access": "false",
        "journal_container": "ephemeral",
        "isolation_attested": "true",
        "strict_schema": "true",
        "repair_used": "false",
        "model_call_count": calls,
        "expectation_scored": "true",
        "expectation_pass": "true",
        "inference_latency_ms": inference,
        "end_to_end_latency_ms": "1500",
        "peak_rss_bytes": "3000000000",
        "output_kind": "canonical_strict_json",
        "output_sha256": raw_hash,
        "raw_response_sha256": raw_hash,
        "normalization_occurred": "false",
        "normalization_count": "0",
        "normalized_fields": "none",
        "normalized_canonical_sha256": digest("normalized:" + raw_hash),
        "raw_cross_field_contradiction": "false",
        **values,
        "error": "none",
    }
    explicit_updates = updates or {}
    fields.update(explicit_updates)
    if fields["strict_schema"] == "true":
        calculated = ab.semantic_marker_fields(
            ab.semantic_assessment(fields, fixture)
        )
        for key, value in calculated.items():
            if key not in explicit_updates:
                fields[key] = value
        if "expectation_pass" not in explicit_updates:
            fields["expectation_pass"] = fields["subject_technical_pass"]
    else:
        for key in (
            "subject_technical_pass", "bristol_within_one", "bristol_exact",
            "form_exact", "mixed_exact", "full_abstention",
        ):
            fields.setdefault(key, "unavailable")
        fields.setdefault("semantic_points", "-1")
        fields.setdefault("semantic_max_points", "-1")
    outcome = "FAIL" if fields["error"] != "none" else "PASS"
    return ab.PREFIX + outcome + " " + " ".join(
        f"{key}={fields[key]}" for key in ab.MARKER_KEYS
    )


def transcript(arm: str, changes: dict[str, dict[str, str]] | None = None) -> str:
    changes = changes or {}
    return "\n".join(
        marker(arm, fixture, changes.get(fixture.fixture_id)) for fixture in ab.FIXTURES
    ) + "\n"


class RunnerTests(unittest.TestCase):
    def evaluate(
        self,
        changes140: dict[str, dict[str, str]] | None = None,
        changes280: dict[str, dict[str, str]] | None = None,
    ) -> dict:
        with tempfile.TemporaryDirectory(prefix="gi-normalization-ab-") as directory:
            root = pathlib.Path(directory)
            path140 = root / "140.txt"
            path280 = root / "280.txt"
            output = root / "decision.json"
            path140.write_text(transcript("arm140", changes140), encoding="utf-8")
            path280.write_text(transcript("arm280", changes280), encoding="utf-8")
            arguments = [
                "--arm-140-markers", str(path140),
                "--arm-280-markers", str(path280),
                "--output", str(output),
            ]
            self.assertEqual(ab.main(arguments), 0)
            return json.loads(output.read_text(encoding="utf-8"))

    def test_complete_passing_pair_defaults_to_140_without_physical_receipt(self) -> None:
        receipt = self.evaluate()
        self.assertTrue(receipt["arm140"]["passed"])
        self.assertTrue(receipt["arm280"]["passed"])
        self.assertEqual(receipt["decision"]["selected_visual_tokens"], 140)
        self.assertEqual(receipt["arm140"]["bristol_within_one"], 5)
        self.assertEqual(receipt["arm140"]["bristol_exact"], 5)
        self.assertEqual(receipt["arm140"]["predeclared_red_black_denominator"], 12)

    def test_nonstool_uncertain_with_abstention_is_a_hard_gate_pass(self) -> None:
        receipt = self.evaluate(
            {"t08-brown-wood-block": {"stool_presence": "uncertain"}},
            {"t08-brown-wood-block": {"stool_presence": "uncertain"}},
        )
        self.assertTrue(receipt["arm140"]["passed"])
        self.assertTrue(receipt["arm280"]["passed"])

    def test_raw_contradiction_and_normalization_are_aggregated_separately(self) -> None:
        normalized = {
            "normalization_occurred": "true",
            "normalization_count": "1",
            "normalized_fields": "bristol_type.form",
            "raw_cross_field_contradiction": "true",
        }
        receipt = self.evaluate(
            {"t08-brown-wood-block": normalized},
            {"t08-brown-wood-block": normalized},
        )
        self.assertEqual(receipt["arm140"]["raw_cross_field_contradictions"], 1)
        self.assertEqual(receipt["arm140"]["normalizations"], 1)

    def test_semantic_failure_does_not_make_pair_structurally_incomplete(self) -> None:
        bad = {
            "stool_presence": "stool", "bristol_type": "4",
            "form": "smooth_formed", "mixed_form": "no", "apparent_color": "brown",
            "red_appearing_material": "no", "black_tarry_appearance": "no",
            "subject_technical_pass": "false", "full_abstention": "false",
            "expectation_pass": "false", "error": "fixture_expectation_failed",
        }
        receipt = self.evaluate({"t08-brown-wood-block": bad})
        self.assertFalse(receipt["arm140"]["passed"])
        self.assertTrue(receipt["arm280"]["passed"])
        self.assertEqual(receipt["arm140"]["strict_schema_valid"], 12)
        self.assertEqual(receipt["arm280"]["strict_schema_valid"], 12)

    def test_late_inference_disqualifies_arm_but_other_arm_is_evaluated(self) -> None:
        late = {
            "inference_latency_ms": "30001",
            "end_to_end_latency_ms": "31000",
            "error": "inference_deadline_exceeded",
        }
        receipt = self.evaluate({"t12-type4-cold-start": late})
        self.assertFalse(receipt["arm140"]["passed"])
        self.assertTrue(receipt["arm280"]["passed"])
        self.assertEqual(receipt["decision"]["selected_visual_tokens"], 280)
        self.assertFalse(receipt["decision"]["promotion_qualified"])

    def test_caught_runtime_timeout_is_semantic_and_other_arm_is_evaluated(self) -> None:
        unavailable = {
            "strict_schema": "false", "quality_gate": "unavailable",
            "model_call_count": "-1", "expectation_scored": "false",
            "expectation_pass": "not_scored", "inference_latency_ms": "-1",
            "end_to_end_latency_ms": "30000", "output_kind": "unavailable",
            "output_sha256": "unavailable", "raw_response_sha256": "unavailable",
            "normalization_occurred": "unavailable",
            "normalization_count": "unavailable", "normalized_fields": "unavailable",
            "normalized_canonical_sha256": "unavailable",
            "raw_cross_field_contradiction": "unavailable",
            "image_usable": "unavailable", "retake_reason": "unavailable",
            "stool_presence": "unavailable", "bristol_type": "unavailable",
            "form": "unavailable", "mixed_form": "unavailable",
            "apparent_color": "unavailable", "red_appearing_material": "unavailable",
            "black_tarry_appearance": "unavailable",
            "error": "inference_deadline_exceeded",
        }
        receipt = self.evaluate({"t12-type4-cold-start": unavailable})
        self.assertFalse(receipt["arm140"]["passed"])
        self.assertTrue(receipt["arm280"]["passed"])
        self.assertIn(
            "t12-type4-cold-start:inference_deadline",
            receipt["arm140"]["errors"],
        )

    def test_strict_cross_field_failure_is_separate_from_normalization(self) -> None:
        unavailable = {
            "strict_schema": "false", "expectation_scored": "false",
            "expectation_pass": "not_scored",
            "output_kind": "raw_response_sha256_only",
            "normalization_occurred": "unavailable",
            "normalization_count": "unavailable", "normalized_fields": "unavailable",
            "normalized_canonical_sha256": "unavailable",
            "raw_cross_field_contradiction": "true",
            "image_usable": "unavailable", "retake_reason": "unavailable",
            "stool_presence": "unavailable", "bristol_type": "unavailable",
            "form": "unavailable", "mixed_form": "unavailable",
            "apparent_color": "unavailable", "red_appearing_material": "unavailable",
            "black_tarry_appearance": "unavailable",
            "error": "strict_schema_inconsistent",
        }
        receipt = self.evaluate({"t12-type4-cold-start": unavailable})
        self.assertEqual(receipt["arm140"]["raw_cross_field_contradictions"], 1)
        self.assertEqual(receipt["arm140"]["normalizations"], 0)
        self.assertEqual(receipt["arm140"]["strict_cross_field_failures"], 1)

    def test_280_semantic_gains_remain_pending_bound_physical_gate(self) -> None:
        losses = {
            "t12-type4-cold-start": {"red_appearing_material": "not_sure"},
            "t01-type1-brown-lumps": {"black_tarry_appearance": "not_sure"},
        }
        receipt = self.evaluate(losses)
        self.assertEqual(receipt["decision"]["selected_visual_tokens"], 140)
        self.assertFalse(receipt["decision"]["promotion_qualified"])
        self.assertTrue(receipt["decision"]["physical_gate_open"])
        self.assertEqual(len(receipt["decision"]["280_fixed_semantic_errors"]), 2)
        self.assertFalse(receipt["arm140"]["semantic_vector"][
            "t12-type4-cold-start:red"
        ])
        self.assertFalse(receipt["arm140"]["semantic_vector"][
            "t01-type1-brown-lumps:black"
        ])
        self.assertTrue(receipt["arm280"]["semantic_vector"][
            "t12-type4-cold-start:red"
        ])
        self.assertTrue(receipt["arm280"]["semantic_vector"][
            "t01-type1-brown-lumps:black"
        ])

    def test_forged_bristol_and_form_score_tokens_are_rejected(self) -> None:
        forged = {
            "bristol_type": "3",
            "form": "cracked_formed",
            "bristol_within_one": "true",
            "bristol_exact": "true",
            "form_exact": "true",
        }
        with self.assertRaises(ab.ContractError):
            self.evaluate({"t12-type4-cold-start": forged})

    def test_forged_subject_and_abstention_score_tokens_are_rejected(self) -> None:
        forged = {
            "stool_presence": "stool",
            "bristol_type": "4",
            "form": "smooth_formed",
            "mixed_form": "no",
            "apparent_color": "brown",
            "red_appearing_material": "no",
            "black_tarry_appearance": "no",
            "subject_technical_pass": "true",
            "full_abstention": "true",
            "expectation_pass": "true",
        }
        with self.assertRaises(ab.ContractError):
            self.evaluate({"t08-brown-wood-block": forged})

    def test_cross_arm_frozen_field_drift_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gi-normalization-ab-drift-") as directory:
            root = pathlib.Path(directory)
            path140, path280 = root / "140.txt", root / "280.txt"
            path140.write_text(transcript("arm140"), encoding="utf-8")
            path280.write_text(
                transcript("arm280", {"t12-type4-cold-start": {"prompt_sha256": "f" * 64}}),
                encoding="utf-8",
            )
            with self.assertRaises(ab.ContractError):
                ab.main([
                    "--arm-140-markers", str(path140),
                    "--arm-280-markers", str(path280),
                    "--output", str(root / "decision.json"),
                ])

    def test_controller_is_exact_24_launch_source_and_preserves_consumed_v9(self) -> None:
        source = CONTROLLER.read_text(encoding="utf-8")
        self.assertIn("for arm_index in {1..2}", source)
        self.assertIn("for fixture_index in {1..12}", source)
        self.assertIn('[[ "$run_count" == "24"', source)
        self.assertIn("--internal-gi-v1-photo-full-prefill-normalized-140", source)
        self.assertIn("--internal-gi-v1-photo-full-prefill-normalized-280", source)
        self.assertIn("--console", source)
        self.assertIn('>"$console_path"', source)
        self.assertIn('wait "$active_capture_pid"', source)
        self.assertNotIn("--stdout=", source)
        self.assertNotIn("--stderr=", source)
        self.assertNotIn("simctl install", source)
        self.assertNotIn("get_app_container", source)
        self.assertNotIn("simctl uninstall", source)
        self.assertNotIn("]##", source)
        self.assertEqual(
            ab.sha256_file(ROOT / "RunRawPhotoV12TuningSimulator.sh"),
            "b07334de7da989f192e224fbc55c1916d7c4cc31ba02e8814bfac820953c0911",
        )

    def test_controller_validates_arguments_before_any_simctl_action(self) -> None:
        valid_udid = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        valid_bundle = "com.omairmkhan.GITimeline.fullprefillnormab20260813a"
        with tempfile.TemporaryDirectory(prefix="gi-normalization-existing-") as output:
            valid = subprocess.run(
                [
                    "/bin/zsh", str(CONTROLLER),
                    "--udid", valid_udid,
                    "--bundle-id", valid_bundle,
                    "--output", output,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(valid.returncode, 73)
            self.assertIn("Output must be a new absolute path.", valid.stderr)
            self.assertNotIn("Usage:", valid.stderr)

            for invalid_udid, invalid_bundle in (
                ("invalid/udid", valid_bundle),
                (valid_udid, "invalid_bundle"),
            ):
                with self.subTest(
                    udid=invalid_udid,
                    bundle=invalid_bundle,
                ):
                    invalid = subprocess.run(
                        [
                            "/bin/zsh", str(CONTROLLER),
                            "--udid", invalid_udid,
                            "--bundle-id", invalid_bundle,
                            "--output", output,
                        ],
                        check=False,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(invalid.returncode, 64)
                    self.assertIn(
                        "Usage: RunFullPrefillNormalizationABSimulator.sh",
                        invalid.stderr,
                    )
                    self.assertNotIn("simctl", invalid.stderr)

    def test_fresh_lane_reads_only_exact_hash_checked_bundle_resources(self) -> None:
        source = HARNESS_SOURCE.read_text(encoding="utf-8")
        start = source.index("final class RawPhotoV12TuningHarness")
        end = source.rindex("\n#endif", start)
        harness = source[start:end]
        self.assertIn("Bundle.main.resourceURL", harness)
        self.assertIn("FullPrefillNormalizationABV1", source)
        self.assertIn("validateBundledInputRoot", harness)
        self.assertIn("foundFiles == expectedFiles", harness)
        self.assertNotIn(".documentDirectory", harness)
        self.assertNotIn("create: true", harness)
        self.assertNotIn("FullPrefillNormalizationABV1", PROJECT_SOURCE.read_text(
            encoding="utf-8"
        ))


if __name__ == "__main__":
    unittest.main()
