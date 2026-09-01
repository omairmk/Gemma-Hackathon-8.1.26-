#!/usr/bin/python3

"""Compare archive and exported app payloads outside legitimate re-signing files."""

import hashlib
import os
import stat
import sys
from pathlib import Path
from typing import Dict, Tuple


def fail(message: str) -> None:
    raise SystemExit(f"error: normalized app-payload comparison failed: {message}")


if len(sys.argv) != 3:
    fail("usage: CompareNormalizedAppPayloadFiles.py ARCHIVE_APP EXPORTED_APP")

archive_root = Path(sys.argv[1])
exported_root = Path(sys.argv[2])
for root, label in ((archive_root, "archive"), (exported_root, "exported")):
    if not root.is_absolute() or not root.is_dir() or root.is_symlink():
        fail(f"{label} app root must be an absolute, non-symlink directory")

special_macho_paths = {
    "GITimeline",
}


def is_resigning_path(relative_path: str) -> bool:
    parts = relative_path.split("/")
    return relative_path == "embedded.mobileprovision" or "_CodeSignature" in parts


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inventory(root: Path, label: str) -> Tuple[Dict[str, int], Dict[str, Tuple[int, int, str]]]:
    directories: Dict[str, int] = {".": stat.S_IMODE(root.lstat().st_mode)}
    files: Dict[str, Tuple[int, int, str]] = {}
    for current_root, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_root)
        relative_current = current.relative_to(root)

        retained_directories = []
        for directory_name in directory_names:
            directory = current / directory_name
            relative = (relative_current / directory_name).as_posix()
            metadata = directory.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                fail(f"{label} payload contains a symlink at {relative}")
            if not stat.S_ISDIR(metadata.st_mode):
                fail(f"{label} payload contains a non-directory node at {relative}")
            if is_resigning_path(relative):
                continue
            directories[relative] = stat.S_IMODE(metadata.st_mode)
            retained_directories.append(directory_name)
        directory_names[:] = retained_directories

        for file_name in file_names:
            path = current / file_name
            relative = (relative_current / file_name).as_posix()
            metadata = path.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                fail(f"{label} payload contains a non-regular file at {relative}")
            if is_resigning_path(relative) or relative in special_macho_paths:
                continue
            files[relative] = (
                stat.S_IMODE(metadata.st_mode),
                metadata.st_size,
                sha256(path),
            )
    return directories, files


archive_directories, archive_files = inventory(archive_root, "archive")
exported_directories, exported_files = inventory(exported_root, "exported")

if archive_directories != exported_directories:
    missing = sorted(set(archive_directories) - set(exported_directories))
    added = sorted(set(exported_directories) - set(archive_directories))
    mode_drift = sorted(
        path
        for path in set(archive_directories) & set(exported_directories)
        if archive_directories[path] != exported_directories[path]
    )
    fail(
        "directory set/mode drifted"
        f"; missing={missing[:1] or '-'} added={added[:1] or '-'} mode={mode_drift[:1] or '-'}"
    )

if archive_files != exported_files:
    missing = sorted(set(archive_files) - set(exported_files))
    added = sorted(set(exported_files) - set(archive_files))
    content_drift = sorted(
        path
        for path in set(archive_files) & set(exported_files)
        if archive_files[path] != exported_files[path]
    )
    fail(
        "non-signing file set/content drifted"
        f"; missing={missing[:1] or '-'} added={added[:1] or '-'} changed={content_drift[:1] or '-'}"
    )

print(
    "NORMALIZED_APP_PAYLOAD_FILES: PASS "
    f"directories={len(archive_directories)} files={len(archive_files)}"
)
