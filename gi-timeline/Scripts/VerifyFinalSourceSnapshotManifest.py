#!/usr/bin/env python3
"""Verify a parent-bound archive seal using immutable Git objects only."""

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


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: VerifyFinalSourceSnapshotManifest.py SEAL_REF", file=sys.stderr)
        return 2

    try:
        root = pathlib.Path(git(pathlib.Path.cwd(), "rev-parse", "--show-toplevel"))
        seal = str(git(root, "rev-parse", f"{sys.argv[1]}^{{commit}}"))
        parents = str(git(root, "show", "-s", "--format=%P", seal)).split()
        if len(parents) != 1:
            fail("seal commit must have exactly one parent")
        source_commit = parents[0]
        manifest_blob = git(root, "show", f"{seal}:{MANIFEST_PATH}", binary=True)
        assert isinstance(manifest_blob, bytes)
        document = json.loads(manifest_blob.decode("utf-8"))

        if document.get("schema") != "gi-journal-final-source-snapshot-v1":
            fail("unsupported manifest schema")
        if document.get("source_commit") != source_commit:
            fail("manifest source_commit does not equal the seal parent")
        source_tree = str(git(root, "rev-parse", f"{source_commit}^{{tree}}"))
        if document.get("source_tree") != source_tree:
            fail("manifest source_tree does not match its source commit")
        if document.get("manifest_path") != MANIFEST_PATH:
            fail("manifest path contract drifted")

        delta = str(git(root, "diff-tree", "--no-commit-id", "--name-status", "-r", source_commit, seal))
        if delta != f"A\t{MANIFEST_PATH}":
            fail(f"seal delta must add only {MANIFEST_PATH}; observed {delta!r}")

        listing = git(root, "ls-tree", "-r", "-z", "--full-tree", source_commit, binary=True)
        assert isinstance(listing, bytes)
        tree: dict[str, tuple[str, str]] = {}
        for record in listing.split(b"\0"):
            if not record:
                continue
            metadata, encoded_path = record.split(b"\t", 1)
            mode, object_type, oid = metadata.decode("ascii").split(" ")
            path = encoded_path.decode("utf-8")
            if object_type != "blob":
                fail(f"unsupported tree entry type {object_type}: {path}")
            tree[path] = (mode, oid)

        entries = document.get("files")
        if not isinstance(entries, list):
            fail("files must be a list")
        paths = [entry.get("path") for entry in entries]
        if paths != sorted(paths) or len(paths) != len(set(paths)):
            fail("manifest paths must be unique and sorted")
        if set(paths) != set(tree):
            fail("manifest path set does not exactly match the source tree")
        if document.get("file_count") != len(entries):
            fail("file_count does not match entries")

        aggregate = hashlib.sha256()
        for entry in entries:
            path = entry["path"]
            pure_path = pathlib.PurePosixPath(path)
            if pure_path.is_absolute() or ".." in pure_path.parts:
                fail(f"unsafe path: {path}")
            mode, oid = tree[path]
            if entry.get("mode") != mode or entry.get("git_oid") != oid:
                fail(f"Git metadata mismatch: {path}")
            blob = git(root, "cat-file", "blob", oid, binary=True)
            assert isinstance(blob, bytes)
            digest = hashlib.sha256(blob).hexdigest()
            if entry.get("bytes") != len(blob):
                fail(f"byte-size mismatch: {path}")
            if entry.get("sha256") != digest:
                fail(f"SHA-256 mismatch: {path}")
            aggregate.update(
                f"{path}\0{mode}\0{oid}\0{len(blob)}\0{digest}\n".encode("utf-8")
            )

        if document.get("aggregate_sha256") != aggregate.hexdigest():
            fail("aggregate SHA-256 mismatch")

        print(
            "FINAL_SOURCE_SNAPSHOT_MANIFEST: PASS "
            f"seal={seal} source_commit={source_commit} files={len(entries)}"
        )
        return 0
    except (KeyError, UnicodeDecodeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FINAL_SOURCE_SNAPSHOT_MANIFEST: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
