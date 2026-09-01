#!/usr/bin/env python3
"""Statically validate Gemma 4 E4B text-prefill context bounds.

This script reads the pinned .litertlm artifact and its embedded TFLite graph.
It does not initialize LiteRT-LM, run inference, inspect app data, or use a
device. Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import hashlib
import mmap
import os
from pathlib import Path
import re
import struct
import sys
from typing import Iterable, Optional


MODEL_FILENAME = "gemma-4-E4B-it.litertlm"
EXPECTED_MODEL_BYTES = 3_659_530_240
EXPECTED_MODEL_SHA256 = (
    "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0"
)
EXPECTED_PREFILL_OFFSET = 1_354_334_208
EXPECTED_PREFILL_END = 3_614_377_584
EXPECTED_SUBGRAPHS = 1_340
EXPECTED_DYNAMIC_UPDATE_SLICE_OPS = 302
EXPECTED_SENTINEL_OPERAND_OPS = 302
EXPECTED_SENTINEL_UPDATE_OPS = 0
EXPECTED_SHIPPING_CONTEXT = 1_536
CONTEXT_SENTINEL = 32_003
DYNAMIC_UPDATE_SLICE_BUILTIN_CODE = 151
EXPECTED_INVALID_COUNTS = {1_024: 20, 1_535: 0, 1_536: 0}
EXPECTED_1024_VIOLATION = (
    (1, 2, 4_096, 1_024),
    (1, 2, 4_096, 1_535),
)


class ValidationError(Exception):
    """Raised when an artifact or graph invariant does not match."""


class FlatBufferReader:
    """Small bounds-checked reader for the table/vector features used here."""

    def __init__(self, data: mmap.mmap, lower: int, upper: int, label: str):
        if lower < 0 or upper <= lower or upper > len(data):
            raise ValidationError(f"invalid {label} byte range [{lower}, {upper})")
        self.data = data
        self.lower = lower
        self.upper = upper
        self.label = label

    def _require(self, offset: int, size: int) -> None:
        if size < 0 or offset < self.lower or offset + size > self.upper:
            raise ValidationError(
                f"{self.label} read [{offset}, {offset + size}) is out of bounds"
            )

    def bytes(self, offset: int, size: int) -> bytes:
        self._require(offset, size)
        return self.data[offset : offset + size]

    def u8(self, offset: int) -> int:
        self._require(offset, 1)
        return self.data[offset]

    def i8(self, offset: int) -> int:
        self._require(offset, 1)
        return struct.unpack_from("<b", self.data, offset)[0]

    def u16(self, offset: int) -> int:
        self._require(offset, 2)
        return struct.unpack_from("<H", self.data, offset)[0]

    def u32(self, offset: int) -> int:
        self._require(offset, 4)
        return struct.unpack_from("<I", self.data, offset)[0]

    def i32(self, offset: int) -> int:
        self._require(offset, 4)
        return struct.unpack_from("<i", self.data, offset)[0]

    def u64(self, offset: int) -> int:
        self._require(offset, 8)
        return struct.unpack_from("<Q", self.data, offset)[0]

    def uoffset_target(self, offset: int) -> int:
        target = offset + self.u32(offset)
        self._require(target, 1)
        return target

    def table_field(self, table: int, index: int) -> Optional[int]:
        self._require(table, 4)
        vtable = table - self.i32(table)
        self._require(vtable, 4)
        vtable_size = self.u16(vtable)
        object_size = self.u16(vtable + 2)
        if vtable_size < 4 or vtable_size % 2:
            raise ValidationError(f"malformed {self.label} vtable at byte {vtable}")
        self._require(vtable, vtable_size)
        self._require(table, object_size)
        entry = vtable + 4 + (2 * index)
        if entry + 2 > vtable + vtable_size:
            return None
        relative = self.u16(entry)
        if relative == 0:
            return None
        if relative >= object_size:
            raise ValidationError(
                f"malformed {self.label} table field {index} at byte {table}"
            )
        field = table + relative
        self._require(field, 1)
        return field

    def vector(self, field: int, element_size: int) -> tuple[int, int]:
        vector = self.uoffset_target(field)
        length = self.u32(vector)
        elements = vector + 4
        self._require(elements, length * element_size)
        return elements, length

    def table_vector(self, field: int) -> list[int]:
        elements, length = self.vector(field, 4)
        result = []
        for index in range(length):
            element = elements + (4 * index)
            result.append(self.uoffset_target(element))
        return result

    def int32_vector(self, field: int) -> list[int]:
        elements, length = self.vector(field, 4)
        return [self.i32(elements + (4 * index)) for index in range(length)]

    def string(self, field: int) -> str:
        data, length = self.vector(field, 1)
        try:
            return self.bytes(data, length).decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValidationError(f"invalid UTF-8 in {self.label} string") from error


def required_field(reader: FlatBufferReader, table: int, index: int, name: str) -> int:
    field = reader.table_field(table, index)
    if field is None:
        raise ValidationError(f"missing required {reader.label} field: {name}")
    return field


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_model_path(repo_root: Path, requested: Optional[str]) -> Path:
    if requested:
        return Path(requested).expanduser().absolute()
    environment_path = os.environ.get("GEMMA_E4B_SOURCE")
    if environment_path:
        return Path(environment_path).expanduser().absolute()
    return (repo_root.parent / "work" / "models" / MODEL_FILENAME).absolute()


def shipping_context(repo_root: Path) -> int:
    source_path = repo_root / "GITimeline" / "ModelRuntime.swift"
    try:
        source = source_path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValidationError(f"cannot read shipping configuration: {source_path}") from error

    declaration = "static let appStoreRawImageV1 = InferenceConfiguration("
    start = source.find(declaration)
    if start < 0:
        raise ValidationError("shipping appStoreRawImageV1 declaration is missing")
    end = source.find("\n  )", start)
    if end < 0:
        raise ValidationError("shipping appStoreRawImageV1 declaration is malformed")
    matches = re.findall(r"\bmaxNumTokens:\s*([0-9_]+)\s*,", source[start:end])
    if len(matches) != 1:
        raise ValidationError(
            "shipping appStoreRawImageV1 must declare exactly one maxNumTokens value"
        )
    value = int(matches[0].replace("_", ""))
    if value != EXPECTED_SHIPPING_CONTEXT:
        raise ValidationError(
            f"shipping context is {value}; expected {EXPECTED_SHIPPING_CONTEXT}"
        )
    return value


def metadata_string(
    reader: FlatBufferReader, metadata_record: int
) -> tuple[str, str]:
    key_field = required_field(reader, metadata_record, 0, "metadata key")
    value_type_field = required_field(reader, metadata_record, 1, "metadata value type")
    value_field = required_field(reader, metadata_record, 2, "metadata value")
    if reader.u8(value_type_field) != 9:
        raise ValidationError("expected string-valued LiteRT-LM section metadata")
    value_table = reader.uoffset_target(value_field)
    string_field = required_field(reader, value_table, 0, "metadata string")
    return reader.string(key_field), reader.string(string_field)


def find_prefill_section(data: mmap.mmap) -> tuple[int, int]:
    reader = FlatBufferReader(data, 0, len(data), "LiteRT-LM container")
    if reader.bytes(0, 8) != b"LITERTLM":
        raise ValidationError("model does not have the LITERTLM container magic")
    if reader.u32(8) != 1:
        raise ValidationError(f"unsupported LiteRT-LM version {reader.u32(8)}")

    root_buffer = 32
    root = reader.uoffset_target(root_buffer)
    sections_table_field = required_field(reader, root, 1, "sections table")
    sections_table = reader.uoffset_target(sections_table_field)
    sections_field = required_field(reader, sections_table, 0, "sections")

    matches = []
    for section in reader.table_vector(sections_field):
        metadata_field = required_field(reader, section, 0, "section metadata")
        start_field = required_field(reader, section, 1, "section start")
        end_field = required_field(reader, section, 2, "section end")
        section_type_field = required_field(reader, section, 3, "section type")
        section_start = reader.u64(start_field)
        section_end = reader.u64(end_field)
        if section_start >= section_end or section_end > len(data):
            raise ValidationError(
                f"invalid LiteRT-LM section range [{section_start}, {section_end})"
            )

        metadata = {}
        for record in reader.table_vector(metadata_field):
            key, value = metadata_string(reader, record)
            if key in metadata:
                raise ValidationError(f"duplicate section metadata key: {key}")
            metadata[key] = value
        if metadata.get("model_type") == "tf_lite_prefill_decode":
            if reader.u8(section_type_field) != 3:
                raise ValidationError("prefill/decode section is not a TFLite section")
            matches.append((section_start, section_end))

    if len(matches) != 1:
        raise ValidationError(
            f"expected one tf_lite_prefill_decode section; found {len(matches)}"
        )
    section_start, section_end = matches[0]
    if (section_start, section_end) != (
        EXPECTED_PREFILL_OFFSET,
        EXPECTED_PREFILL_END,
    ):
        raise ValidationError(
            "prefill/decode section range does not match the pinned artifact: "
            f"[{section_start}, {section_end})"
        )
    return section_start, section_end


def builtin_operator_code(reader: FlatBufferReader, operator_code: int) -> int:
    current_field = reader.table_field(operator_code, 3)
    if current_field is not None:
        return reader.i32(current_field)
    deprecated_field = reader.table_field(operator_code, 0)
    return reader.i8(deprecated_field) if deprecated_field is not None else 0


def substituted(shape: Iterable[int], context: int) -> tuple[int, ...]:
    return tuple(context if dimension == CONTEXT_SENTINEL else dimension for dimension in shape)


def violates_dynamic_update_slice(
    operand_shape: tuple[int, ...], update_shape: tuple[int, ...]
) -> bool:
    return len(operand_shape) != len(update_shape) or any(
        update > operand for operand, update in zip(operand_shape, update_shape)
    )


def inspect_prefill_graph(
    data: mmap.mmap, section_start: int, section_end: int
) -> tuple[int, int, int, dict[int, list[tuple[tuple[int, ...], tuple[int, ...]]]]]:
    reader = FlatBufferReader(data, section_start, section_end, "TFLite prefill graph")
    if reader.bytes(section_start + 4, 4) != b"TFL3":
        raise ValidationError("prefill/decode section does not have the TFL3 identifier")
    root = reader.uoffset_target(section_start)
    operator_codes_field = required_field(reader, root, 1, "operator codes")
    subgraphs_field = required_field(reader, root, 2, "subgraphs")
    operator_codes = [
        builtin_operator_code(reader, table)
        for table in reader.table_vector(operator_codes_field)
    ]
    if operator_codes.count(DYNAMIC_UPDATE_SLICE_BUILTIN_CODE) != 1:
        raise ValidationError(
            "expected one DYNAMIC_UPDATE_SLICE operator-code entry in prefill graph"
        )

    subgraphs = reader.table_vector(subgraphs_field)
    invalid_by_context = {context: [] for context in EXPECTED_INVALID_COUNTS}
    dynamic_update_slice_count = 0
    sentinel_operand_count = 0
    sentinel_update_count = 0

    for subgraph in subgraphs:
        tensors_field = required_field(reader, subgraph, 0, "subgraph tensors")
        operators_field = required_field(reader, subgraph, 3, "subgraph operators")
        tensors = reader.table_vector(tensors_field)
        for operator in reader.table_vector(operators_field):
            opcode_index_field = reader.table_field(operator, 0)
            opcode_index = reader.u32(opcode_index_field) if opcode_index_field else 0
            if opcode_index >= len(operator_codes):
                raise ValidationError(f"operator-code index {opcode_index} is out of range")
            if operator_codes[opcode_index] != DYNAMIC_UPDATE_SLICE_BUILTIN_CODE:
                continue

            dynamic_update_slice_count += 1
            inputs_field = required_field(reader, operator, 1, "operator inputs")
            inputs = reader.int32_vector(inputs_field)
            if len(inputs) != 3:
                raise ValidationError(
                    "DYNAMIC_UPDATE_SLICE operator does not have exactly three inputs"
                )
            operand_index, update_index = inputs[:2]
            if not (0 <= operand_index < len(tensors)) or not (
                0 <= update_index < len(tensors)
            ):
                raise ValidationError("DYNAMIC_UPDATE_SLICE tensor index is out of range")

            operand_shape_field = required_field(
                reader, tensors[operand_index], 0, "operand shape"
            )
            update_shape_field = required_field(
                reader, tensors[update_index], 0, "update shape"
            )
            operand_shape = tuple(reader.int32_vector(operand_shape_field))
            update_shape = tuple(reader.int32_vector(update_shape_field))
            if not operand_shape or any(dimension <= 0 for dimension in operand_shape):
                raise ValidationError("DYNAMIC_UPDATE_SLICE operand has an invalid shape")
            if not update_shape or any(dimension <= 0 for dimension in update_shape):
                raise ValidationError("DYNAMIC_UPDATE_SLICE update has an invalid shape")

            if CONTEXT_SENTINEL in operand_shape:
                sentinel_operand_count += 1
            if CONTEXT_SENTINEL in update_shape:
                sentinel_update_count += 1
            for context in invalid_by_context:
                concrete_operand = substituted(operand_shape, context)
                concrete_update = substituted(update_shape, context)
                if violates_dynamic_update_slice(concrete_operand, concrete_update):
                    invalid_by_context[context].append(
                        (concrete_operand, concrete_update)
                    )

    if len(subgraphs) != EXPECTED_SUBGRAPHS:
        raise ValidationError(
            f"prefill graph has {len(subgraphs)} subgraphs; expected {EXPECTED_SUBGRAPHS}"
        )
    if dynamic_update_slice_count != EXPECTED_DYNAMIC_UPDATE_SLICE_OPS:
        raise ValidationError(
            "prefill graph has "
            f"{dynamic_update_slice_count} DYNAMIC_UPDATE_SLICE operators; "
            f"expected {EXPECTED_DYNAMIC_UPDATE_SLICE_OPS}"
        )
    if sentinel_operand_count != EXPECTED_SENTINEL_OPERAND_OPS:
        raise ValidationError(
            f"sentinel appears in {sentinel_operand_count} DYNAMIC_UPDATE_SLICE operands; "
            f"expected {EXPECTED_SENTINEL_OPERAND_OPS}"
        )
    if sentinel_update_count != EXPECTED_SENTINEL_UPDATE_OPS:
        raise ValidationError(
            f"sentinel appears in {sentinel_update_count} DYNAMIC_UPDATE_SLICE updates; "
            f"expected {EXPECTED_SENTINEL_UPDATE_OPS}"
        )
    for context, expected in EXPECTED_INVALID_COUNTS.items():
        actual = len(invalid_by_context[context])
        if actual != expected:
            raise ValidationError(
                f"context {context} has {actual} invalid DYNAMIC_UPDATE_SLICE operators; "
                f"expected {expected}"
            )
    if set(invalid_by_context[1_024]) != {EXPECTED_1024_VIOLATION}:
        raise ValidationError("context 1024 has an unexpected violating shape pair")

    return (
        len(subgraphs),
        dynamic_update_slice_count,
        sentinel_operand_count,
        invalid_by_context,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Statically prove the pinned Gemma E4B text-prefill graph fails "
            "DYNAMIC_UPDATE_SLICE bounds at context 1024 and passes at 1535/1536."
        )
    )
    parser.add_argument(
        "--model",
        metavar="PATH",
        help=(
            "pinned .litertlm path (default: GEMMA_E4B_SOURCE, then the "
            "repository's ../work/models path)"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    model_path = resolve_model_path(repo_root, args.model)
    context = shipping_context(repo_root)

    if model_path.is_symlink() or not model_path.is_file():
        raise ValidationError(
            f"model is missing or is not a regular non-symlink file: {model_path}"
        )
    model_bytes = model_path.stat().st_size
    if model_bytes != EXPECTED_MODEL_BYTES:
        raise ValidationError(
            f"model size is {model_bytes}; expected {EXPECTED_MODEL_BYTES} bytes"
        )
    model_sha256 = sha256(model_path)
    if model_sha256 != EXPECTED_MODEL_SHA256:
        raise ValidationError(
            f"model SHA-256 is {model_sha256}; expected {EXPECTED_MODEL_SHA256}"
        )

    with model_path.open("rb") as model_file, mmap.mmap(
        model_file.fileno(), 0, access=mmap.ACCESS_READ
    ) as data:
        section_start, section_end = find_prefill_section(data)
        subgraphs, dus_ops, sentinel_ops, invalid = inspect_prefill_graph(
            data, section_start, section_end
        )

    print(f"GEMMA_PREFILL_CONTEXT_VALIDATION: model={model_path}")
    print(
        "PINNED_ARTIFACT: PASS "
        f"bytes={model_bytes} sha256={model_sha256}"
    )
    print(
        "TEXT_PREFILL_SECTION: PASS "
        f"type=tf_lite_prefill_decode offset={section_start} "
        f"bytes={section_end - section_start}"
    )
    print(
        "GRAPH_INVENTORY: PASS "
        f"subgraphs={subgraphs} dynamic_update_slice_ops={dus_ops} "
        f"sentinel={CONTEXT_SENTINEL} sentinel_operand_ops={sentinel_ops}"
    )
    for candidate_context in sorted(EXPECTED_INVALID_COUNTS):
        count = len(invalid[candidate_context])
        result = "FAILS_GRAPH_BOUNDS" if count else "PASSES_GRAPH_BOUNDS"
        label = " shipping=true" if candidate_context == context else ""
        detail = ""
        if candidate_context == 1_024:
            operand, update = EXPECTED_1024_VIOLATION
            detail = (
                f" violating_operand={list(operand)} violating_update={list(update)}"
                f" violating_pair_count={count}"
            )
        print(
            f"CONTEXT_CHECK: context={candidate_context}{label} "
            f"invalid_dynamic_update_slice_ops={count} result={result}{detail}"
        )
    print(
        "GEMMA_PREFILL_CONTEXT_VALIDATION: PASS "
        "expected_contrast=1024_fails_shipping_1536_passes"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"GEMMA_PREFILL_CONTEXT_VALIDATION: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
    except OSError as error:
        print(
            f"GEMMA_PREFILL_CONTEXT_VALIDATION: FAIL: cannot read model: {error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
