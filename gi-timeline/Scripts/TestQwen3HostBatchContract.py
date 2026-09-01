#!/usr/bin/env python3
"""Deterministic no-model tests for the DEV-only host semantic proxy batch."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest


RUNNER_PATH = Path(__file__).with_name("RunQwen3HostSemanticProxy.py")


def load_runner() -> object:
    spec = importlib.util.spec_from_file_location("qwen3_host_batch_runner", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("runner must be importable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runner = load_runner()


class HostBatchContractTests(unittest.TestCase):
    def test_dev_manifest_accepts_only_hash_bound_opaque_dev_sources(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dev = Path(temporary) / "dev"
            dev.mkdir()
            first = dev / "0123456789abcdefabcd.png"
            second = dev / "fedcba9876543210fedc.png"
            first.write_bytes(b"synthetic-one")
            second.write_bytes(b"synthetic-two")
            manifest = dev / "manifest.json"
            manifest.write_text(json.dumps({
                "schema": "gi-qwen-fixture-manifest-v2",
                "set": "dev",
                "synthetic_only": True,
                "images": [
                    {"file": first.name, "sha256": hashlib.sha256(first.read_bytes()).hexdigest(),
                     "expected": {"subject": "must-not-enter-selection"}},
                    {"file": second.name, "sha256": hashlib.sha256(second.read_bytes()).hexdigest()},
                ],
            }))

            selected = runner.select_fixtures(None, manifest)

            self.assertEqual([item.fixture_id for item in selected.fixtures], [first.stem, second.stem])
            self.assertEqual(selected.dev_manifest_sha256, runner.sha256_path(manifest))
            self.assertFalse(hasattr(selected.fixtures[0], "expected"))

    def test_holdout_path_is_rejected_before_manifest_is_opened(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            holdout = Path(temporary) / "holdout"
            holdout.mkdir()
            malformed = holdout / "manifest.json"
            malformed.write_text("not json")

            with self.assertRaisesRegex(RuntimeError, "holdout input is forbidden"):
                runner.select_fixtures(None, malformed)

    def test_non_dev_or_hash_mismatched_manifest_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = root / "0123456789abcdefabcd.png"
            fixture.write_bytes(b"synthetic")
            manifest = root / "manifest.json"
            base = {
                "schema": "gi-qwen-fixture-manifest-v2",
                "set": "dev",
                "synthetic_only": True,
                "images": [{"file": fixture.name, "sha256": "0" * 64}],
            }
            manifest.write_text(json.dumps(base))
            with self.assertRaisesRegex(RuntimeError, "source hash mismatch"):
                runner.select_fixtures(None, manifest)
            base["set"] = "holdout"
            manifest.write_text(json.dumps(base))
            with self.assertRaisesRegex(RuntimeError, "set=dev"):
                runner.select_fixtures(None, manifest)

    def test_repeatable_explicit_fixture_selection_preserves_legacy_single_form(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = root / "named-synthetic.png"
            fixture.write_bytes(b"synthetic")

            selected = runner.select_fixtures([fixture], None)

            self.assertEqual(len(selected.fixtures), 1)
            self.assertEqual(selected.fixtures[0].fixture_id, hashlib.sha256(b"synthetic").hexdigest()[:20])

    def test_mock_generation_emits_exact_seven_nonempty_fresh_calls(self) -> None:
        prompts = [
            {"field": field, "prompt": f"prompt-{field}", "promptSHA256": hashlib.sha256(field.encode()).hexdigest()}
            for field in runner.EXPECTED_FIELDS
        ]
        preparation = {"derivativePNGPath": "/synthetic/app-derived-512.png", "prompts": prompts}
        calls: list[tuple[str, str]] = []

        def apply_template(_processor: object, _config: object, prompt: str, **_kwargs: object) -> str:
            return f"formatted:{prompt}"

        def stream_generate(_model: object, _processor: object, prompt: str, **kwargs: object):
            calls.append((prompt, str(kwargs["image"])))
            yield SimpleNamespace(
                token=100 + len(calls), text=f"answer-{len(calls)}", finish_reason="length",
                prompt_tokens=5, generation_tokens=1, peak_memory=0.25,
            )

        fields = runner.generate_fields(
            preparation, SimpleNamespace(config=object()), object(), stream_generate, apply_template
        )

        self.assertEqual([item["field"] for item in fields], runner.EXPECTED_FIELDS)
        self.assertEqual([item["model_call_ordinal"] for item in fields], list(range(1, 8)))
        self.assertTrue(all(item["raw_text"] and item["raw_token_ids"] for item in fields))
        self.assertTrue(all(item["latency_milliseconds"] > 0 for item in fields))
        self.assertTrue(all(item["used_fresh_generation_cache"] is True for item in fields))
        self.assertEqual(len(calls), 7)
        self.assertTrue(all(image == preparation["derivativePNGPath"] for _, image in calls))

    def test_empty_generation_and_qualified_fusion_fail_closed(self) -> None:
        invalid = [{
            "field": field, "raw_text": "", "raw_utf8_sha256": hashlib.sha256(b"").hexdigest(),
            "raw_token_ids": [], "model_call_ordinal": ordinal,
            "latency_milliseconds": 1, "used_fresh_generation_cache": True,
        } for ordinal, field in enumerate(runner.EXPECTED_FIELDS, start=1)]
        with self.assertRaisesRegex(RuntimeError, "empty raw model text"):
            runner.validate_field_evidence(invalid)

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            fields = [{
                "field": field, "raw_text": "answer", "raw_token_ids": [1],
                "latency_milliseconds": 1, "stop_reason": "length",
            } for field in runner.EXPECTED_FIELDS]
            original_run = runner.run

            def fake_run(command: list[str], **_kwargs: object) -> SimpleNamespace:
                fused_path = Path(command[command.index("--output") + 1])
                fused_path.write_text(json.dumps({
                    "schemaVersion": "qwen3-host-semantic-proxy-evidence-v1",
                    "promptSetSHA256": "a" * 64,
                    "runEvidence": {"fields": [
                        {"field": field, "qualified": field == "subject"}
                        for field in runner.EXPECTED_FIELDS
                    ]},
                }))
                return SimpleNamespace()

            runner.run = fake_run
            try:
                with self.assertRaisesRegex(RuntimeError, "escaped the forced-unqualified boundary"):
                    runner.fuse_fixture(output, {"prompts": []}, fields, "swift", Path(temporary))
            finally:
                runner.run = original_run

    def test_source_has_one_model_load_site_and_explicit_proxy_label(self) -> None:
        source = RUNNER_PATH.read_text()
        self.assertEqual(source.count("model, processor = load("), 1)
        self.assertIn("model_load_count\": 1", source)
        self.assertIn("NOT DEVICE OR RELEASE EVIDENCE", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
