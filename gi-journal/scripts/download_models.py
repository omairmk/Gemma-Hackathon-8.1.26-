"""Download the two frozen Prompt A model artifacts into workspace-local HF cache."""

from __future__ import annotations

import json
import os
from pathlib import Path

from huggingface_hub import snapshot_download


def load_manifest(root: Path) -> dict:
    return json.loads((root / "model_manifest.json").read_text())


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    hf_home = Path(os.environ.get("HF_HOME", root / ".hf_cache")).resolve()
    hf_home.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(root)
    records = []
    for key, spec in manifest["models"].items():
        path = snapshot_download(repo_id=spec["model_id"], revision=spec["revision"], cache_dir=str(hf_home))
        relative_path = Path(path).resolve().relative_to(root).as_posix()
        if relative_path != spec["snapshot_path"]:
            raise RuntimeError(f"Pinned snapshot mismatch for {key}: {relative_path}")
        records.append({"key": key, **spec})
        print(json.dumps(records[-1], sort_keys=True), flush=True)
    (root / "model_downloads.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    main()
