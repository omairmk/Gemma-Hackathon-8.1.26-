#!/usr/bin/env python3
"""Verify the public source snapshot without trusting Git's working tree."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: VerifySourceSnapshotManifest.py MANIFEST.json", file=sys.stderr)
        return 2

    manifest_path = pathlib.Path(sys.argv[1]).resolve()
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    root = manifest_path.parents[3]
    failures: list[str] = []

    for item in document["files"]:
        relative = pathlib.PurePosixPath(item["path"])
        if relative.is_absolute() or ".." in relative.parts:
            failures.append(f"unsafe manifest path: {relative}")
            continue
        path = root.joinpath(*relative.parts)
        if not path.is_file():
            failures.append(f"missing: {relative}")
            continue
        actual_size = path.stat().st_size
        actual_hash = sha256(path)
        if actual_size != item["bytes"]:
            failures.append(
                f"size mismatch: {relative}: {actual_size} != {item['bytes']}"
            )
        if actual_hash != item["sha256"]:
            failures.append(f"hash mismatch: {relative}")

    expected_paths = {item["path"] for item in document["files"]}
    actual_paths = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
        and ".git" not in path.relative_to(root).parts
        and path.resolve() != manifest_path
    }
    missing_from_manifest = sorted(actual_paths - expected_paths)
    if missing_from_manifest:
        failures.append(
            "unmanifested files: " + ", ".join(missing_from_manifest)
        )

    if failures:
        for failure in failures:
            print(f"SOURCE_SNAPSHOT_MANIFEST: FAIL: {failure}", file=sys.stderr)
        return 1

    print(
        "SOURCE_SNAPSHOT_MANIFEST: PASS "
        f"files={len(document['files'])} source={document['source_commit']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
