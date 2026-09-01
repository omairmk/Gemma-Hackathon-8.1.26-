#!/usr/bin/python3
"""Focused tests for the internal 1024 Qwen QA resolution contract."""

from __future__ import annotations

import copy
import importlib.util
import re
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = ROOT / "Scripts" / "ValidateQwen3ResolutionEvidence.py"
SPEC = importlib.util.spec_from_file_location("qwen_resolution_evidence", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
resolution = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = resolution
SPEC.loader.exec_module(resolution)


class Qwen3ResolutionEvidenceContractTests(unittest.TestCase):
    maxDiff = None

    def current_records(
        self,
        profile: str,
        *,
        source_width: int | None = None,
        source_height: int | None = None,
    ) -> list[dict]:
        contract = resolution.PROFILE_CONTRACTS[profile]
        source_width = source_width or contract.derivative_edge
        source_height = source_height or contract.derivative_edge
        content_width = contract.derivative_edge
        content_height = max(1, source_height * contract.derivative_edge // source_width)
        if content_height > contract.derivative_edge:
            content_height = contract.derivative_edge
            content_width = max(1, source_width * contract.derivative_edge // source_height)
        source_hash = "a" * 64
        deterministic_hash = (
            "b" * 64 if contract.derivative_edge == 512 else "d" * 64
        )
        request_id = "request-1"
        shared = {
            "schemaVersion": resolution.CURRENT_SCHEMA,
            "timestamp": "2026-08-31T12:00:00Z",
            "thermalState": "nominal",
        }
        records = [
            {**shared, "event": "journal_ready", "profile": profile},
            {
                **shared,
                "event": "request_started",
                "profile": profile,
                "requestID": request_id,
                "analyzedImageSHA256": source_hash,
                "analyzedPixelWidth": source_width,
                "analyzedPixelHeight": source_height,
                "requestedProfile": profile,
                "effectiveProfile": profile,
                "preprocessingVersion": contract.preprocessing_version,
                "sourcePixelWidth": source_width,
                "sourcePixelHeight": source_height,
                "derivativePixelWidth": contract.derivative_edge,
                "derivativePixelHeight": contract.derivative_edge,
                "pixelBudget": contract.pixel_budget,
                "expectedFrameT": 1,
                "expectedFrameH": contract.frame_edge,
                "expectedFrameW": contract.frame_edge,
                "postMergeVisualTokenCount": contract.post_merge_visual_tokens,
            },
            {
                **shared,
                "event": "preprocess_completed",
                "profile": profile,
                "requestID": request_id,
                "analyzedImageSHA256": source_hash,
                "requestedProfile": profile,
                "effectiveProfile": profile,
                "preprocessingVersion": contract.preprocessing_version,
                "sourcePixelWidth": source_width,
                "sourcePixelHeight": source_height,
                "effectiveSourcePixelWidth": min(source_width, content_width),
                "effectiveSourcePixelHeight": min(source_height, content_height),
                "derivativePixelWidth": contract.derivative_edge,
                "derivativePixelHeight": contract.derivative_edge,
                "derivativeContentPixelWidth": content_width,
                "derivativeContentPixelHeight": content_height,
                "deterministicDerivativePixelWidth": 512,
                "deterministicDerivativePixelHeight": 512,
                "deterministicDerivativeRGBASHA256": deterministic_hash,
                "sourceWasUpscaled": content_width > source_width or content_height > source_height,
                "pixelBudget": contract.pixel_budget,
                "expectedFrameT": 1,
                "expectedFrameH": contract.frame_edge,
                "expectedFrameW": contract.frame_edge,
                "frameT": 1,
                "frameH": contract.frame_edge,
                "frameW": contract.frame_edge,
                "postMergeVisualTokenCount": contract.post_merge_visual_tokens,
                "derivativeRGBASHA256": "b" * 64,
                "preparedTensorSHA256": "c" * 64,
                "preprocessLatencyMilliseconds": 42,
                "availableMemoryBytes": 2_700_000_000,
                "mlxActiveMemoryBytes": 1_800_000_000,
                "mlxPeakMemoryBytes": 2_360_000_000,
                "mlxCacheMemoryBytes": 1_700_000_000,
                "hostPeakRSSBytes": 1_980_000_000,
            },
        ]
        if contract.semantically_admitted:
            records.append(
                {
                    **shared,
                    "event": "request_completed",
                    "profile": profile,
                    "requestID": request_id,
                    "analyzedImageSHA256": source_hash,
                    "modelCallCount": 7,
                    "requestLatencyMilliseconds": 4_200,
                }
            )
        return records

    def historical_records(self, profile: str) -> list[dict]:
        contract = resolution.PROFILE_CONTRACTS[profile]
        shared = {
            "schemaVersion": resolution.HISTORICAL_SCHEMA,
            "timestamp": "2026-08-28T12:00:00Z",
            "thermalState": "nominal",
        }
        return [
            {**shared, "event": "journal_ready", "profile": profile},
            {
                **shared,
                "event": "request_started",
                "profile": profile,
                "requestID": "historical-request",
                "analyzedImageSHA256": "d" * 64,
                "analyzedPixelWidth": 512,
                "analyzedPixelHeight": 512,
            },
            {
                **shared,
                "event": "preprocess_completed",
                "profile": profile,
                "requestID": "historical-request",
                "analyzedImageSHA256": "d" * 64,
                "preparedTensorSHA256": "e" * 64,
                "frameT": 1,
                "frameH": contract.frame_edge,
                "frameW": contract.frame_edge,
            },
        ]

    def validate(self, records: list[dict], profile: str, current: bool = True) -> int:
        return resolution.validate_records(
            records, profile, require_current_schema=current
        )

    def test_profile_constants_pin_requested_budgets_and_frames(self) -> None:
        self.assertEqual(
            {
                key: (
                    value.derivative_edge,
                    value.pixel_budget,
                    value.frame_edge,
                    value.post_merge_visual_tokens,
                    value.semantically_admitted,
                )
                for key, value in resolution.PROFILE_CONTRACTS.items()
            },
            {
                "1024": (1024, 1_048_576, 64, 1_024, True),
                "512": (512, 262_144, 32, 256, True),
                "256": (512, 65_536, 16, 64, False),
            },
        )

    def test_current_1024_receipt_binds_exact_derivative_and_frame(self) -> None:
        self.assertEqual(self.validate(self.current_records("1024"), "1024"), 1)

    def test_current_512_and_256_receipts_remain_valid(self) -> None:
        self.assertEqual(self.validate(self.current_records("512"), "512"), 1)
        self.assertEqual(self.validate(self.current_records("256"), "256"), 1)

    def test_unsupported_profile_is_rejected(self) -> None:
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "exactly"):
            self.validate(self.current_records("512"), "768")

    def test_wrong_1024_patch_grid_is_rejected(self) -> None:
        records = self.current_records("1024")
        records[2]["frameH"] = 32
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "actual processor frame"):
            self.validate(records, "1024")

    def test_unsupported_derivative_dimensions_are_rejected(self) -> None:
        records = self.current_records("1024")
        records[2]["derivativePixelWidth"] = 768
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "unsupported"):
            self.validate(records, "1024")

    def test_deterministic_derivative_receipt_is_exact_and_hash_pinned(self) -> None:
        for field, value, message in (
            ("deterministicDerivativePixelWidth", 1024, "exactly 512x512"),
            ("deterministicDerivativePixelHeight", 256, "exactly 512x512"),
            ("deterministicDerivativeRGBASHA256", "not-a-hash", "hash is invalid"),
        ):
            with self.subTest(field=field):
                records = self.current_records("1024")
                records[2][field] = value
                with self.assertRaisesRegex(resolution.ResolutionEvidenceError, message):
                    self.validate(records, "1024")

    def test_admitted_completion_requires_exact_nonnegative_total_latency(self) -> None:
        for value in (None, -1, True):
            with self.subTest(value=value):
                records = self.current_records("1024")
                if value is None:
                    records[3].pop("requestLatencyMilliseconds")
                else:
                    records[3]["requestLatencyMilliseconds"] = value
                with self.assertRaisesRegex(
                    resolution.ResolutionEvidenceError, "nonnegative integer"
                ):
                    self.validate(records, "1024")

    def test_smaller_source_records_upscale_without_claiming_added_detail(self) -> None:
        records = self.current_records("1024", source_width=400, source_height=300)
        preprocess = records[2]
        self.assertTrue(preprocess["sourceWasUpscaled"])
        self.assertEqual(preprocess["effectiveSourcePixelWidth"], 400)
        self.assertEqual(preprocess["effectiveSourcePixelHeight"], 300)
        self.assertEqual(self.validate(records, "1024"), 1)

    def test_false_upscale_flag_and_overclaimed_effective_size_are_rejected(self) -> None:
        baseline = self.current_records("1024", source_width=400, source_height=300)
        false_flag = copy.deepcopy(baseline)
        false_flag[2]["sourceWasUpscaled"] = False
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "truthful"):
            self.validate(false_flag, "1024")
        overclaim = copy.deepcopy(baseline)
        overclaim[2]["effectiveSourcePixelWidth"] = 1024
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "overclaims"):
            self.validate(overclaim, "1024")

    def test_hidden_1024_to_512_fallback_is_rejected(self) -> None:
        records = self.current_records("1024")
        records[2]["effectiveProfile"] = "512"
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "hidden fallback"):
            self.validate(records, "1024")

    def test_historical_512_and_256_preprocess_receipts_replay(self) -> None:
        self.assertEqual(self.validate(self.historical_records("512"), "512", False), 1)
        self.assertEqual(self.validate(self.historical_records("256"), "256", False), 1)

    def test_historical_schema_cannot_claim_1024_and_is_not_current_evidence(self) -> None:
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "never established"):
            self.validate(self.historical_records("1024"), "1024", False)
        with self.assertRaisesRegex(resolution.ResolutionEvidenceError, "requires v2"):
            self.validate(self.historical_records("512"), "512", True)

    def test_engine_source_keeps_explicit_fallback_and_cancellation_boundaries(self) -> None:
        source = (ROOT / "GITimeline" / "Qwen3HybridPhotoSuggestionEngine.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn('case pixels1024 = "1024"', source)
        self.assertIn('case "--qwen3-decomposed-preprocess=1024": return .pixels1024', source)
        self.assertIn('event: "retry_at_512_available"', source)
        self.assertIn("automatic_fallback=false", source)
        self.assertIn("withTaskCancellationHandler", source)
        self.assertIn("preparationTask.cancel()", source)
        self.assertIn("activeTask.cancel()", source)
        self.assertIn('event: "cancellation_requested"', source)
        self.assertIn("maxTokens: 8", source)
        self.assertNotIn("maxTokens: 16", source)

        prepare_source = source[
            source.index("func prepare() async throws") : source.index(
                "func suggest(_ input:", source.index("func prepare() async throws")
            )
        ]
        for awaited_value in (
            "try await preparationTask.value",
            "try await task.value",
        ):
            with self.subTest(awaited_value=awaited_value):
                awaited = prepare_source.index(awaited_value)
                cancellation_check = prepare_source.index(
                    "try Task.checkCancellation()", awaited
                )
                resource_assignment = prepare_source.index("resources = loaded", awaited)
                self.assertLess(awaited, cancellation_check)
                self.assertLess(cancellation_check, resource_assignment)

        host_source = (
            ROOT / "Tools" / "Qwen3HostEvidenceFuse" / "main.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            'preprocessingVersion: "qwen3vl-hybrid-512-v2-preprocessing-evidence"',
            host_source,
        )
        self.assertIn("let baselinePrepared = try HybridImagePreparer.prepare(", host_source)
        self.assertRegex(
            host_source,
            re.compile(
                r"pixelEvidence:\s*HybridPixelAnalyzer\.evaluate\(deterministicFrame\)"
            ),
        )
        self.assertNotIn(
            "pixelEvidence: HybridPixelAnalyzer.evaluate(derivativeFrame)", host_source
        )

        host_runner_source = (ROOT / "Scripts" / "RunQwen3HostDevAB.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("qwen3vl-hybrid-512-v2-preprocessing-evidence", host_runner_source)

        physical_runner_source = (
            ROOT / "Scripts" / "RunQwen3PhysicalQualification.sh"
        ).read_text(encoding="utf-8")
        self.assertIn(
            'completed[0].get("requestLatencyMilliseconds")', physical_runner_source
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
