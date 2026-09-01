#!/usr/bin/env python3
"""No-model contract tests for the fixed Qwen3 synthetic DEV A/B runner."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import ast
from types import SimpleNamespace
import tempfile
import time
import unittest


RUNNER_PATH = Path(__file__).with_name("RunQwen3HostDevAB.py")
EVALUATOR_PATH = RUNNER_PATH.parents[1] / "handoff-2026-08-22-linux-surface/qwen-mild-utility-v3-2026-08-31/evaluator/score_mild_utility_v3.py"


def load_runner() -> object:
    spec = importlib.util.spec_from_file_location("qwen3_host_dev_ab_runner", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("runner must be importable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_evaluator() -> object:
    spec = importlib.util.spec_from_file_location("qwen3_mild_utility_evaluator", EVALUATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("evaluator must be importable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


runner = load_runner()
evaluator = load_evaluator()


def sealed(value: dict[str, object]) -> dict[str, object]:
    return runner.seal_artifact(value)


class HostDevABContractTests(unittest.TestCase):
    def usable_preparation(self, color_confidence: int = 800_000) -> dict[str, object]:
        return {
            "pixelEvidence": {
                "quality": "usable",
                "baseColorConfidencePPM": color_confidence,
            }
        }

    def fixture_id(self, index: int) -> str:
        return f"{index:020x}"

    def expected_labels(self, index: int) -> dict[str, str]:
        if index >= 20:
            return {
                "subject": "control", "color": "not_sure", "bristol_band": "not_sure",
                "red": "no", "dark_black": "no", "glossy_tarlike": "no",
            }
        return {
            "subject": "stool",
            "color": ("brown_tan", "yellow", "green", "red", "dark_black")[index % 5],
            "bristol_band": ("hard", "formed", "loose_mushy", "watery")[index % 4],
            "red": "yes" if index < 3 else "no",
            "dark_black": "yes" if index < 3 else "no",
            "glossy_tarlike": "yes" if index < 3 else "no",
        }

    def make_inputs(self, root: Path) -> tuple[Path, Path, Path, Path, Path]:
        fixtures = root / "fixtures"
        fixtures.mkdir()
        blind_rows = []
        review_rows = []
        candidates = []
        for index in range(29):
            fixture_id = self.fixture_id(index + 1)
            payload = f"synthetic-{index}".encode("ascii")
            source_sha = hashlib.sha256(payload).hexdigest()
            if index < 28:
                (fixtures / f"{fixture_id}.png").write_bytes(payload)
            blind_rows.append({"fixture_id": fixture_id, "source_sha256": source_sha, "width": 512, "height": 512})
            review_rows.append({
                "fixture_id": fixture_id,
                "source_sha256": source_sha,
                "decision": "admit",
                "realism_reason": "",
                "discernibility": {field: "discernible" for field in evaluator.FIELDS},
            })
            candidates.append({"fixture_id": fixture_id, "source_sha256": source_sha})
        blind_input = sealed({
            "schema": evaluator.BLIND_INPUT_SCHEMA,
            "dataset_id": "synthetic-dev-ab-v1",
            "split": "dev",
            "labels_visible": False,
            "fixtures": blind_rows,
        })
        blind_input_path = root / "blind-input.json"
        blind_input_path.write_text(json.dumps(blind_input), encoding="utf-8")
        blind_review = sealed({
            "schema": evaluator.BLIND_REVIEW_SCHEMA,
            "dataset_id": "synthetic-dev-ab-v1",
            "split": "dev",
            "blind_input_sha256": blind_input["artifact_sha256"],
            "reviewer_id_hash": "a" * 64,
            "reviewer_independence_attested": True,
            "intended_labels_visible": False,
            "rows": review_rows,
        })
        blind_review_path = root / "blind-review.json"
        blind_review_path.write_text(json.dumps(blind_review), encoding="utf-8")
        admitted = []
        for index, candidate in enumerate(candidates[:28]):
            review = review_rows[index]
            admitted.append({
                **candidate,
                "review_row_sha256": runner.object_sha256(review),
                "scene_family_id": f"scene-{index + 1}",
                "template_family_id": f"template-{index + 1}",
                "prompt_family_id": f"prompt-{index + 1}",
                "seed_family_id": f"seed-{index + 1}",
                "reproducibility_id": f"repro-{index + 1}",
                "ahash": hashlib.sha256(f"ahash-{index}".encode()).hexdigest(),
                "dhash": hashlib.sha256(f"dhash-{index}".encode()).hexdigest()[:16],
                "phash": hashlib.sha256(f"phash-{index}".encode()).hexdigest()[:16],
            })
        not_selected_candidate = candidates[-1]
        admission = sealed({
            "schema": runner.ADMISSION_SCHEMA,
            "dataset_id": "synthetic-dev-ab-v1",
            "split": "dev",
            "blind_review_sha256": blind_review["artifact_sha256"],
            "admitted": admitted,
            "rejected": [],
            "not_selected": [{
                **not_selected_candidate,
                "review_row_sha256": runner.object_sha256(review_rows[-1]),
            }],
        })
        admission_path = root / "admission.json"
        admission_path.write_text(json.dumps(admission), encoding="utf-8")
        evaluation = sealed({
            "schema": runner.LABELS_SCHEMA,
            "dataset_id": "synthetic-dev-ab-v1",
            "split": "dev",
            "admission_manifest_sha256": admission["artifact_sha256"],
            "frozen_before_inference": True,
            "fixtures": [
                {**candidate, "expected": self.expected_labels(index)}
                for index, candidate in enumerate(candidates[:28])
            ],
        })
        labels_path = root / "labels.json"
        labels_path.write_text(json.dumps(evaluation), encoding="utf-8")
        return blind_input_path, blind_review_path, admission_path, labels_path, fixtures

    def rewrite_admission(
        self, admission_path: Path, labels_path: Path, **changes: object
    ) -> tuple[dict[str, object], dict[str, object]]:
        admission = json.loads(admission_path.read_text())
        admission.pop("artifact_sha256")
        admission.update(changes)
        sealed(admission)
        admission_path.write_text(json.dumps(admission), encoding="utf-8")
        labels = json.loads(labels_path.read_text())
        labels.pop("artifact_sha256")
        labels["admission_manifest_sha256"] = admission["artifact_sha256"]
        sealed(labels)
        labels_path.write_text(json.dumps(labels), encoding="utf-8")
        return admission, labels

    def rewrite_labels(self, labels_path: Path, **changes: object) -> dict[str, object]:
        labels = json.loads(labels_path.read_text())
        labels.pop("artifact_sha256")
        labels.update(changes)
        sealed(labels)
        labels_path.write_text(json.dumps(labels), encoding="utf-8")
        return labels

    def test_exact_fixed_plan_has_196_plus_84_calls_and_global_ordinals(self) -> None:
        fixtures = tuple(
            runner.Fixture(self.fixture_id(index + 1), "a" * 64, Path(f"/{index}.png"))
            for index in range(28)
        )
        plan = runner.build_plan(fixtures)

        self.assertEqual(len(plan), 280)
        self.assertEqual([call.global_ordinal for call in plan], list(range(1, 281)))
        self.assertEqual(sum(call.configuration_id == "qwen3vl_decomposed_512" for call in plan), 196)
        self.assertEqual(sum(call.configuration_id == "qwen3vl_subset_768" for call in plan), 84)
        self.assertEqual([call.model_field for call in plan[:7]], list(runner.MODEL_FIELDS))
        self.assertEqual([call.model_field for call in plan[196:199]], ["subject", "bristol", "color"])

    def test_source_exposes_one_model_load_site_and_no_variant_cli_switches(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        ast.parse(source)
        self.assertEqual(source.count("model, processor = load("), 1)
        self.assertIn("MAX_CAMPAIGN_CALLS = 280", source)
        self.assertIn("MODEL_REVISION = \"9c4f5209e57b31f4b9dfba735de3fb983739c9cc\"", source)
        self.assertIn("--blind-input", source)
        self.assertIn("--blind-review", source)
        self.assertIn("validate_evaluator_preflight(", source)
        self.assertLess(source.index("inputs = load_dev_inputs("), source.index("import mlx.core as mx"))
        self.assertNotIn("--resolution", source)
        self.assertNotIn("--max-tokens", source)
        self.assertNotIn("--retry", source)

    def test_mock_generation_preserves_raw_bytes_tokens_timing_memory_and_global_ordinal(self) -> None:
        preparation = {
            "derivativePNGPath": "/tmp/prepared.png",
            "prompts": [
                {"field": field, "prompt": f"prompt-{field}", "promptSHA256": hashlib.sha256(field.encode()).hexdigest()}
                for field in runner.MODEL_FIELDS
            ],
        }

        def apply_template(_processor: object, _config: object, prompt: str, **_kwargs: object) -> str:
            return f"formatted:{prompt}"

        def stream_generate(_model: object, _processor: object, _prompt: str, **_kwargs: object):
            yield SimpleNamespace(token=17, text="stool", finish_reason="length", prompt_tokens=5, generation_tokens=1, peak_memory=0.5)

        evidence = runner.generate_one(
            model=SimpleNamespace(config=SimpleNamespace()), processor=SimpleNamespace(),
            stream_generate=stream_generate, apply_chat_template=apply_template,
            mx=SimpleNamespace(get_peak_memory=lambda: 1234), preparation=preparation,
            field="subject", global_ordinal=1, fixture_call_ordinal=1,
        )
        self.assertEqual(evidence["global_ordinal"], 1)
        self.assertEqual(evidence["raw_utf8_base64"], "c3Rvb2w=")
        self.assertEqual(evidence["raw_utf8_sha256"], hashlib.sha256(b"stool").hexdigest())
        self.assertEqual(evidence["raw_token_ids"], [17])
        self.assertEqual(evidence["mlx_peak_memory_bytes"], 1234)

    def test_stuck_generation_hits_wall_clock_timeout_and_next_call_is_clean(self) -> None:
        preparation = {
            "derivativePNGPath": "/tmp/prepared.png",
            "prompts": [
                {"field": field, "prompt": f"prompt-{field}", "promptSHA256": hashlib.sha256(field.encode()).hexdigest()}
                for field in runner.MODEL_FIELDS
            ],
        }

        def apply_template(_processor: object, _config: object, prompt: str, **_kwargs: object) -> str:
            return f"formatted:{prompt}"

        def stuck_stream(_model: object, _processor: object, _prompt: str, **_kwargs: object):
            time.sleep(0.1)
            yield SimpleNamespace(token=17, text="stool", finish_reason="length")

        previous_handler = signal.getsignal(signal.SIGALRM)
        started = time.perf_counter()
        timed_out = runner.generate_one(
            model=SimpleNamespace(config=SimpleNamespace()), processor=SimpleNamespace(),
            stream_generate=stuck_stream, apply_chat_template=apply_template,
            mx=SimpleNamespace(get_peak_memory=lambda: 0), preparation=preparation,
            field="subject", global_ordinal=1, fixture_call_ordinal=1, timeout_milliseconds=5,
        )
        self.assertLess(time.perf_counter() - started, 0.5)
        self.assertTrue(timed_out["timed_out"])
        self.assertEqual(timed_out["stop_reason"], "timeout")
        self.assertEqual(timed_out["raw_text"], "")
        self.assertEqual(timed_out["raw_token_ids"], [])
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous_handler)
        response = runner.response_record(
            {"records": [{"invoked": True, "parsed": {"disposition": "invalid"}}]},
            {"subject": timed_out},
        )
        self.assertTrue(response["timed_out"])
        self.assertTrue(response["safely_converted_to_not_sure"])

        def quick_stream(_model: object, _processor: object, _prompt: str, **_kwargs: object):
            yield SimpleNamespace(token=18, text="stool", finish_reason="length")

        following = runner.generate_one(
            model=SimpleNamespace(config=SimpleNamespace()), processor=SimpleNamespace(),
            stream_generate=quick_stream, apply_chat_template=apply_template,
            mx=SimpleNamespace(get_peak_memory=lambda: 0), preparation=preparation,
            field="subject", global_ordinal=2, fixture_call_ordinal=1, timeout_milliseconds=50,
        )
        self.assertFalse(following["timed_out"])
        self.assertEqual(following["raw_text"], "stool")

    def test_hash_bound_admission_labels_and_exact_opaque_fixture_root_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission, labels, fixtures = self.make_inputs(root)
            inputs = runner.load_dev_inputs(blind_input, blind_review, admission, labels, fixtures)
            self.assertEqual(len(inputs.fixtures), 28)
            self.assertEqual(inputs.fixtures[0].fixture_id, self.fixture_id(1))

            (fixtures / "extra.png").write_bytes(b"unexpected")
            with self.assertRaisesRegex(runner.ContractFailure, "exactly the sealed"):
                runner.load_dev_inputs(blind_input, blind_review, admission, labels, fixtures)

    def test_optional_not_selected_is_accepted_but_never_enters_fixture_root_or_plan(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission_path, labels_path, fixtures = self.make_inputs(root)
            not_selected_id = json.loads(admission_path.read_text())["not_selected"][0]["fixture_id"]

            inputs = runner.load_dev_inputs(blind_input, blind_review, admission_path, labels_path, fixtures)
            plan = runner.build_plan(inputs.fixtures)

            self.assertEqual(len(inputs.fixtures), 28)
            self.assertFalse((fixtures / f"{not_selected_id}.png").exists())
            self.assertNotIn(not_selected_id, {fixture.fixture_id for fixture in inputs.fixtures})
            self.assertNotIn(not_selected_id, {call.fixture_id for call in plan})

    def test_malformed_or_overlapping_not_selected_inventory_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission_path, labels_path, fixtures = self.make_inputs(root)
            first = json.loads(admission_path.read_text())["admitted"][0]
            self.rewrite_admission(
                admission_path,
                labels_path,
                not_selected=[{
                    "fixture_id": first["fixture_id"],
                    "source_sha256": first["source_sha256"],
                    "review_row_sha256": first["review_row_sha256"],
                }],
            )
            with self.assertRaisesRegex(runner.ContractFailure, "admitted and not_selected"):
                runner.load_dev_inputs(blind_input, blind_review, admission_path, labels_path, fixtures)

            self.rewrite_admission(
                admission_path,
                labels_path,
                not_selected=[{
                    "fixture_id": "e" * 20,
                    "source_sha256": hashlib.sha256(b"eligible-not-selected").hexdigest(),
                    "review_row_sha256": "c" * 64,
                    "decision": "reject",
                }],
            )
            with self.assertRaisesRegex(runner.ContractFailure, "keys mismatch"):
                runner.load_dev_inputs(blind_input, blind_review, admission_path, labels_path, fixtures)

    def test_tampered_labels_and_holdout_path_fail_before_model_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission, labels, fixtures = self.make_inputs(root)
            value = json.loads(labels.read_text())
            value["frozen_before_inference"] = False
            labels.write_text(json.dumps(value))
            with self.assertRaisesRegex(runner.ContractFailure, "artifact hash mismatch"):
                runner.load_dev_inputs(blind_input, blind_review, admission, labels, fixtures)

            holdout = root / "holdout-fixtures"
            holdout.mkdir()
            with self.assertRaisesRegex(runner.ContractFailure, "holdout path is forbidden"):
                runner.load_dev_inputs(blind_input, blind_review, admission, labels, holdout)

    def test_evaluator_preflight_rejects_admission_missing_required_metadata_without_model_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission_path, labels_path, fixtures = self.make_inputs(root)
            admitted = json.loads(admission_path.read_text())["admitted"]
            admitted[0].pop("scene_family_id")
            self.rewrite_admission(admission_path, labels_path, admitted=admitted)

            with self.assertRaisesRegex(runner.ContractFailure, "admission.admitted\\[0\\] keys mismatch"):
                runner.load_dev_inputs(blind_input, blind_review, admission_path, labels_path, fixtures)

    def test_evaluator_preflight_rejects_empty_expected_labels_without_model_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission, labels_path, fixtures = self.make_inputs(root)
            label_rows = json.loads(labels_path.read_text())["fixtures"]
            label_rows[0]["expected"] = {}
            self.rewrite_labels(labels_path, fixtures=label_rows)

            with self.assertRaisesRegex(runner.ContractFailure, "labels.fixtures\\[0\\].expected keys mismatch"):
                runner.load_dev_inputs(blind_input, blind_review, admission, labels_path, fixtures)

    def test_evaluator_preflight_rejects_bad_label_distribution_without_model_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission, labels_path, fixtures = self.make_inputs(root)
            label_rows = json.loads(labels_path.read_text())["fixtures"]
            label_rows[0]["expected"] = {
                "subject": "control", "color": "not_sure", "bristol_band": "not_sure",
                "red": "no", "dark_black": "no", "glossy_tarlike": "no",
            }
            self.rewrite_labels(labels_path, fixtures=label_rows)

            with self.assertRaisesRegex(runner.ContractFailure, "exactly 20 stool fixtures, got 19"):
                runner.load_dev_inputs(blind_input, blind_review, admission, labels_path, fixtures)

    def test_shared_subset_receipt_maps_uninvoked_safety_to_not_sure(self) -> None:
        receipt = {
            "records": [
                {
                    "field": field,
                    "invoked": field in {"subject", "bristol", "color"},
                    "parsed": {
                        "label": {"subject": "stool", "bristol": "4", "color": "brown"}.get(field, "unsure"),
                        "disposition": "accepted" if field in {"subject", "bristol", "color"} else "invalid",
                    },
                }
                for field in runner.MODEL_FIELDS
            ]
        }
        values = runner.labels_to_values(runner.parsed_labels(receipt))
        self.assertEqual(values["subject"], "stool")
        self.assertEqual(values["bristol_band"], "formed")
        self.assertEqual(values["color"], "brown_tan")
        self.assertEqual(values["red"], "not_sure")
        self.assertEqual(values["dark_black"], "not_sure")
        self.assertEqual(values["glossy_tarlike"], "not_sure")
        displayed = runner.stage(values)
        self.assertEqual(displayed["safety_hints"], {
            "red": "AI suggestion: Unable to determine whether blood-like red material is visible.",
            "dark_black": "AI suggestion: Unable to determine whether a black or tar-like appearance is visible.",
            "glossy_tarlike": "AI suggestion: Unable to determine whether a black or tar-like appearance is visible.",
        })

    def test_negative_model_labels_map_to_no_and_exact_copy(self) -> None:
        labels = {
            "subject": "unsure", "bristol": "unsure", "mixed": "unsure", "color": "unsure",
            "red": "no", "black": "no", "glossy": "no",
        }
        values = runner.labels_to_values(labels)
        self.assertEqual(values["red"], "no")
        self.assertEqual(values["dark_black"], "no")
        self.assertEqual(values["glossy_tarlike"], "no")
        self.assertEqual(runner.stage(values)["safety_hints"], {
            "red": "AI suggestion: No blood-like red material detected in this photo.",
            "dark_black": "AI suggestion: No black or tar-like appearance detected in this photo.",
            "glossy_tarlike": "AI suggestion: No black or tar-like appearance detected in this photo.",
        })

    def test_shared_swift_subset_parser_receipt_keeps_uninvoked_fields_not_sure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "input.json"
            output_path = root / "output.json"
            input_path.write_text(json.dumps({"fields": [
                {"field": "subject", "rawText": "stool"},
                {"field": "bristol", "rawText": "4"},
                {"field": "color", "rawText": "brown"},
            ]}), encoding="utf-8")
            result = subprocess.run(
                ["swift", "run", "Qwen3HostEvidenceFuse", "parse-subset", "--input", str(input_path), "--output", str(output_path)],
                cwd=RUNNER_PATH.parents[1], check=True, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0)
            receipt = json.loads(output_path.read_text())
            self.assertEqual(receipt["schemaVersion"], "qwen3-host-dev-ab-shared-parser-subset-v1")
            records = {record["field"]: record for record in receipt["records"]}
            self.assertTrue(records["subject"]["invoked"])
            self.assertFalse(records["red"]["invoked"])
            self.assertEqual(records["red"]["parsed"]["label"], "unsure")

    def test_appearance_fusion_admits_matching_positive_and_negative_but_not_disagreement(self) -> None:
        raw = runner.empty_values()
        deterministic = runner.empty_values()
        raw["red"] = "possible_positive"
        deterministic["red"] = "possible_positive"
        raw["dark_black"] = "no"
        deterministic["dark_black"] = "no"
        raw["glossy_tarlike"] = "no"
        deterministic["glossy_tarlike"] = "possible_positive"
        fused = runner.host_fusion_values(raw, deterministic, self.usable_preparation())
        self.assertEqual(fused["red"], "possible_positive")
        self.assertEqual(fused["dark_black"], "no")
        self.assertEqual(fused["glossy_tarlike"], "not_sure")
        displayed = runner.stage(fused)
        self.assertEqual(displayed["values"]["dark_black"], "no")
        self.assertEqual(displayed["safety_hints"], {
            "red": "AI suggestion: Possible blood-like red material is visible.",
            "dark_black": "AI suggestion: No black or tar-like appearance detected in this photo.",
            "glossy_tarlike": "AI suggestion: Unable to determine whether a black or tar-like appearance is visible.",
        })

    def test_tarlike_fusion_requires_matching_black_and_glossy_model_and_pixels(self) -> None:
        for concrete in ("possible_positive", "no"):
            raw = runner.empty_values()
            deterministic = runner.empty_values()
            raw["dark_black"] = concrete
            raw["glossy_tarlike"] = concrete
            deterministic["dark_black"] = concrete
            deterministic["glossy_tarlike"] = concrete
            self.assertEqual(
                runner.host_fusion_values(
                    raw, deterministic, self.usable_preparation()
                )["glossy_tarlike"],
                concrete,
            )

            for missing_lane in (
                (raw, "dark_black"),
                (raw, "glossy_tarlike"),
                (deterministic, "dark_black"),
                (deterministic, "glossy_tarlike"),
            ):
                changed_raw = dict(raw)
                changed_deterministic = dict(deterministic)
                target = changed_raw if missing_lane[0] is raw else changed_deterministic
                target[missing_lane[1]] = "not_sure"
                self.assertEqual(
                    runner.host_fusion_values(
                        changed_raw, changed_deterministic, self.usable_preparation()
                    )["glossy_tarlike"],
                    "not_sure",
                )

    def test_fusion_fails_closed_for_unusable_pixel_quality(self) -> None:
        raw = {field: "possible_positive" for field in runner.VALUE_FIELDS}
        raw.update({"subject": "stool", "color": "brown_tan", "bristol_band": "formed"})
        deterministic = runner.empty_values()
        deterministic.update({
            "color": "brown_tan",
            "red": "possible_positive",
            "dark_black": "possible_positive",
            "glossy_tarlike": "possible_positive",
        })
        preparation = self.usable_preparation()
        preparation["pixelEvidence"]["quality"] = "hard_poor_severe_blur"

        self.assertEqual(
            runner.host_fusion_values(raw, deterministic, preparation),
            runner.empty_values(),
        )

    def test_fusion_never_passes_subject_or_bristol(self) -> None:
        raw = runner.empty_values()
        raw.update({"subject": "stool", "bristol_band": "formed"})
        fused = runner.host_fusion_values(
            raw, runner.empty_values(), self.usable_preparation()
        )
        self.assertEqual(fused["subject"], "not_sure")
        self.assertEqual(fused["bristol_band"], "not_sure")

    def test_color_fusion_requires_app_confidence_threshold(self) -> None:
        raw = runner.empty_values()
        deterministic = runner.empty_values()
        raw["color"] = "brown_tan"
        deterministic["color"] = "brown_tan"

        self.assertEqual(
            runner.host_fusion_values(
                raw, deterministic, self.usable_preparation(549_999)
            )["color"],
            "not_sure",
        )
        self.assertEqual(
            runner.host_fusion_values(
                raw, deterministic, self.usable_preparation(550_000)
            )["color"],
            "brown_tan",
        )

    def test_deterministic_high_negative_maps_to_no_and_ambiguous_or_missing_to_not_sure(self) -> None:
        deterministic = runner.deterministic_values({"pixelEvidence": {
            "baseColorCandidate": "brown",
            "localizedRed": "high_negative",
            "localizedBlack": "ambiguous",
        }})
        self.assertEqual(deterministic["red"], "no")
        self.assertEqual(deterministic["dark_black"], "not_sure")
        self.assertEqual(deterministic["glossy_tarlike"], "not_sure")

    def test_sealed_run_record_is_schema_exact_and_campaign_cap_is_fixed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            blind_input, blind_review, admission_path, labels_path, fixtures_root = self.make_inputs(root)
            inputs = runner.load_dev_inputs(blind_input, blind_review, admission_path, labels_path, fixtures_root)
            config = runner.CONFIGURATIONS[1]
            preparation = {
                "prompts": [
                    {"field": field, "prompt": f"prompt-{field}"}
                    for field in runner.MODEL_FIELDS
                ]
            }
            rows = []
            for fixture in inputs.fixtures:
                values = runner.empty_values()
                rows.append({
                    "fixture_id": fixture.fixture_id,
                    "source_sha256": fixture.source_sha256,
                    "prepared_sha256": hashlib.sha256((fixture.fixture_id + "prepared").encode()).hexdigest(),
                    "request_id": f"req-b-{fixture.fixture_id}",
                    "raw_outputs": {
                        "subject": {"utf8_base64": "c3Rvb2w=", "sha256": hashlib.sha256(b"stool").hexdigest(), "model_call_ordinal": 1},
                        "bristol_band": {"utf8_base64": "NA==", "sha256": hashlib.sha256(b"4").hexdigest(), "model_call_ordinal": 2},
                        "color": {"utf8_base64": "YnJvd24=", "sha256": hashlib.sha256(b"brown").hexdigest(), "model_call_ordinal": 3},
                    },
                    "response": {"raw_schema_valid": True, "safely_converted_to_not_sure": False, "timed_out": False, "malformed": False, "contradictory": False, "missing": False},
                    "model_call_count": 3,
                    "latency_milliseconds": 1,
                    "stages": {name: runner.stage(values) for name in ("raw", "parsed", "deterministic", "fused", "displayed")},
                })
            record = runner.run_record(
                inputs=inputs, config=config, preparation=preparation, fixtures=rows,
                model_safetensors_sha256="b" * 64, plan_sha256="c" * 64,
            )
            self.assertEqual(record["schema"], runner.RUN_SCHEMA)
            self.assertEqual(record["generation_count"], 84)
            self.assertEqual(record["campaign_generation_count"], 280)
            self.assertEqual(record["artifact_sha256"], runner.artifact_sha256(record))
            self.assertNotIn("preparation_scope", record["configuration"])
            labels_by_id = {row["fixture_id"]: row for row in inputs.labels["fixtures"]}
            validated, _ = evaluator.validate_run(record, inputs.admission, inputs.labels, labels_by_id)
            self.assertEqual(validated["generation_count"], 84)


if __name__ == "__main__":
    unittest.main()
