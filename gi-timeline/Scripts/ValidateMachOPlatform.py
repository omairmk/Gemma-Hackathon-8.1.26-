#!/usr/bin/python3

"""Validate the architecture and LC_BUILD_VERSION of a thin release Mach-O."""

import struct
import sys


def fail(message: str) -> None:
    raise SystemExit(f"error: Mach-O platform validation failed: {message}")


if len(sys.argv) != 4:
    fail("usage: ValidateMachOPlatform.py BINARY EXPECTED_PLATFORM EXPECTED_MINIMUM_VERSION")

binary_path, expected_platform_text, expected_minimum_text = sys.argv[1:]
try:
    expected_platform = int(expected_platform_text)
    expected_minimum_parts = tuple(int(part) for part in expected_minimum_text.split("."))
except ValueError:
    fail("expected platform/version arguments are malformed")
if not 1 <= len(expected_minimum_parts) <= 3:
    fail("expected minimum version must have one to three numeric components")
expected_minimum = expected_minimum_parts + (0,) * (3 - len(expected_minimum_parts))

try:
    with open(binary_path, "rb") as binary:
        data = binary.read()
except OSError as error:
    fail(f"could not read executable: {error}")

if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
    fail("executable is not a little-endian 64-bit Mach-O")

_, cpu_type, _, _, command_count, command_bytes, _, _ = struct.unpack_from("<IIIIIIII", data, 0)
if cpu_type != 0x0100000C:
    fail(f"executable CPU type is {cpu_type:#x}, expected arm64")

commands_start = 32
commands_end = commands_start + command_bytes
if commands_end > len(data):
    fail("Mach-O load commands exceed file bounds")

offset = commands_start
observed = []
for _ in range(command_count):
    if offset + 8 > commands_end:
        fail("truncated Mach-O load command")
    command, command_size = struct.unpack_from("<II", data, offset)
    if command_size < 8 or offset + command_size > commands_end:
        fail("invalid Mach-O load command size")
    if command == 0x32:  # LC_BUILD_VERSION
        if command_size < 24:
            fail("truncated LC_BUILD_VERSION")
        _, _, platform, minimum_raw, _, tool_count = struct.unpack_from("<IIIIII", data, offset)
        if command_size != 24 + tool_count * 8:
            fail("LC_BUILD_VERSION tool records do not match command size")
        minimum = (
            (minimum_raw >> 16) & 0xFFFF,
            (minimum_raw >> 8) & 0xFF,
            minimum_raw & 0xFF,
        )
        observed.append((platform, minimum))
    offset += command_size

if offset != commands_end:
    fail("load-command sizes do not equal the Mach-O header declaration")
if len(observed) != 1:
    fail(f"expected exactly one LC_BUILD_VERSION, found {len(observed)}")
platform, minimum = observed[0]
if platform != expected_platform:
    fail(f"platform is {platform}, expected {expected_platform}")
if minimum != expected_minimum:
    fail(f"minimum OS is {minimum[0]}.{minimum[1]}.{minimum[2]}, expected {expected_minimum_text}")

print(
    "MACHO_PLATFORM_VALIDATION: PASS "
    f"platform={platform} minimum={minimum[0]}.{minimum[1]}.{minimum[2]} arch=arm64"
)
