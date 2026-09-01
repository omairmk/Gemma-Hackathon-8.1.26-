#!/usr/bin/python3

"""Hash a signed arm64 Mach-O through its signature blob boundary.

Only load-command fields that codesign legitimately rewrites are normalized.
The Mach-O header, load commands, segments, and non-signature __LINKEDIT data
remain bound by the digest.
"""

import hashlib
import struct
import sys


def fail(message: str) -> None:
    raise SystemExit(f"error: normalized Mach-O hash failed: {message}")


if len(sys.argv) != 3:
    fail("usage: NormalizedMachOExecutableHash.py EXECUTABLE LINKEDIT_FILE_OFFSET")

binary_path = sys.argv[1]
try:
    linkedit_fileoff = int(sys.argv[2])
except ValueError:
    fail("__LINKEDIT file offset is not an integer")

try:
    with open(binary_path, "rb") as binary:
        data = bytearray(binary.read())
except OSError as error:
    fail(f"could not read executable: {error}")

if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
    fail("executable is not a little-endian 64-bit Mach-O")

_, _, _, _, command_count, command_bytes, _, _ = struct.unpack_from("<IIIIIIII", data, 0)
commands_start = 32
commands_end = commands_start + command_bytes
if commands_end > linkedit_fileoff or commands_end > len(data):
    fail("Mach-O load commands exceed the pre-__LINKEDIT region")

offset = commands_start
code_signature_commands = 0
linkedit_segments = 0
for _ in range(command_count):
    if offset + 8 > commands_end:
        fail("truncated Mach-O load command")
    command, command_size = struct.unpack_from("<II", data, offset)
    if command_size < 8 or offset + command_size > commands_end:
        fail("invalid Mach-O load command size")

    if command == 0x1D:  # LC_CODE_SIGNATURE
        if command_size != 16:
            fail("unexpected LC_CODE_SIGNATURE size")
        signature_offset, signature_size = struct.unpack_from("<II", data, offset + 8)
        if signature_size == 0 or signature_offset < linkedit_fileoff:
            fail("LC_CODE_SIGNATURE points outside __LINKEDIT bounds")
        if signature_offset + signature_size != len(data):
            fail("LC_CODE_SIGNATURE is not the exact executable tail")
        data[offset + 8 : offset + 16] = b"\x00" * 8
        code_signature_commands += 1

    if command == 0x19:  # LC_SEGMENT_64
        if command_size < 72:
            fail("truncated LC_SEGMENT_64")
        segment_name = bytes(data[offset + 8 : offset + 24]).split(b"\x00", 1)[0]
        if segment_name == b"__LINKEDIT":
            segment_vmaddr = struct.unpack_from("<Q", data, offset + 24)[0]
            segment_vmsize = struct.unpack_from("<Q", data, offset + 32)[0]
            segment_fileoff = struct.unpack_from("<Q", data, offset + 40)[0]
            segment_filesize = struct.unpack_from("<Q", data, offset + 48)[0]
            if segment_fileoff != linkedit_fileoff:
                fail("LC_SEGMENT_64 __LINKEDIT fileoff does not match measured offset")
            if segment_fileoff + segment_filesize != len(data):
                fail("__LINKEDIT file range is not the exact executable tail")
            # Xcode's deterministic strip step aligns the virtual end of
            # __LINKEDIT to 64 KiB. Standard codesign aligns it to 16 KiB when
            # replacing that signature. Accept exactly those signing layouts;
            # the exact file range and signature tail remain validated above.
            allowed_vmsizes = {
                ((segment_vmaddr + segment_filesize + alignment - 1) & ~(alignment - 1))
                - segment_vmaddr
                for alignment in (0x4000, 0x10000)
            }
            if segment_vmsize not in allowed_vmsizes:
                fail("__LINKEDIT vmsize is not an allowed signing layout")
            # Re-signing replaces the signature tail and may update these sizes.
            # vmaddr/fileoff and all other header/load-command fields remain bound.
            data[offset + 32 : offset + 40] = b"\x00" * 8  # vmsize
            data[offset + 48 : offset + 56] = b"\x00" * 8  # filesize
            linkedit_segments += 1

    offset += command_size

if offset != commands_end:
    fail("load-command sizes do not equal the Mach-O header declaration")
if code_signature_commands != 1 or linkedit_segments != 1:
    fail("Mach-O must have one well-formed LC_CODE_SIGNATURE and __LINKEDIT segment")

print(hashlib.sha256(data[:signature_offset]).hexdigest())
