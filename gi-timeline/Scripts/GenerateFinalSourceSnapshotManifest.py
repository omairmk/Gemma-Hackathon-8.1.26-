#!/usr/bin/env python3
"""Generate a deterministic manifest from an immutable Git content commit."""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys


MANIFEST_PATH = "FINAL_SOURCE_SNAPSHOT_MANIFEST.json"


def git(root: pathlib.Path, *arguments: str, binary: bool = False) -> bytes | str:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout if binary else result.stdout.decode("utf-8").strip()


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: GenerateFinalSourceSnapshotManifest.py SOURCE_COMMIT OUTPUT.json",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(git(pathlib.Path.cwd(), "rev-parse", "--show-toplevel"))
    source_commit = str(git(root, "rev-parse", f"{sys.argv[1]}^{{commit}}"))
    if len(source_commit) != 40:
        raise ValueError("source commit did not resolve to a full object ID")
    source_tree = str(git(root, "rev-parse", f"{source_commit}^{{tree}}"))
    output = pathlib.Path(sys.argv[2]).resolve()
    expected_output = root / MANIFEST_PATH
    if output != expected_output:
        raise ValueError(f"output must be {expected_output}")

    listing = git(root, "ls-tree", "-r", "-z", "--full-tree", source_commit, binary=True)
    assert isinstance(listing, bytes)
    files: list[dict[str, object]] = []
    aggregate = hashlib.sha256()
    for record in listing.split(b"\0"):
        if not record:
            continue
        metadata, encoded_path = record.split(b"\t", 1)
        mode, object_type, oid = metadata.decode("ascii").split(" ")
        path = encoded_path.decode("utf-8")
        if object_type != "blob":
            raise ValueError(f"unsupported tree entry type {object_type}: {path}")
        if path == MANIFEST_PATH:
            raise ValueError("source commit must not already contain the final manifest")
        blob = git(root, "cat-file", "blob", oid, binary=True)
        assert isinstance(blob, bytes)
        digest = hashlib.sha256(blob).hexdigest()
        entry = {
            "path": path,
            "mode": mode,
            "git_oid": oid,
            "bytes": len(blob),
            "sha256": digest,
        }
        files.append(entry)
        aggregate.update(
            f"{path}\0{mode}\0{oid}\0{len(blob)}\0{digest}\n".encode("utf-8")
        )

    document = {
        "schema": "gi-journal-final-source-snapshot-v1",
        "snapshot_kind": "FINAL_MANUAL_FALLBACK_LOCAL_ARCHIVE",
        "branch": "archive/2026-09-01-apple-native-v1",
        "tag": "gi-journal-manual-fallback-v1-2026-09-01",
        "source_commit": source_commit,
        "source_tree": source_tree,
        "manifest_path": MANIFEST_PATH,
        "seal_contract": {
            "seal_has_exactly_one_parent": source_commit,
            "only_change_from_parent": f"A\t{MANIFEST_PATH}",
        },
        "file_count": len(files),
        "aggregate_sha256": aggregate.hexdigest(),
        "files": files,
    }
    output.write_text(json.dumps(document, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(
        "FINAL_SOURCE_SNAPSHOT_MANIFEST: GENERATED "
        f"files={len(files)} source_commit={source_commit} source_tree={source_tree}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
