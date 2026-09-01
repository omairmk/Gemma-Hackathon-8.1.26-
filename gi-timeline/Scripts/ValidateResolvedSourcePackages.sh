#!/bin/zsh

set -euo pipefail

readonly source_packages_path="${1:?usage: ValidateResolvedSourcePackages.sh /absolute/path/SourcePackages}"
readonly project_root="${0:A:h:h}"
readonly workspace_state_path="$source_packages_path/workspace-state.json"
readonly package_resolved_path="$project_root/GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly expected_package_resolved_sha256="90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f"

fail() {
  print -u2 -- "error: resolved source-package validation failed: $1"
  exit 1
}

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

[[ "$source_packages_path" == /* ]] || fail "source-package path must be absolute"
[[ -d "$source_packages_path" && ! -L "$source_packages_path" ]] \
  || fail "source-package root is missing or is a symlink"
[[ -f "$package_resolved_path" && ! -L "$package_resolved_path" ]] \
  || fail "Package.resolved is missing or is a symlink"
[[ -f "$workspace_state_path" && ! -L "$workspace_state_path" ]] \
  || fail "resolved workspace-state.json is missing or is a symlink"
[[ "$(sha256 "$package_resolved_path")" == "$expected_package_resolved_sha256" ]] \
  || fail "Package.resolved SHA-256 drifted"
[[ "$(/usr/bin/plutil -extract pins json -o - "$package_resolved_path")" == "[]" ]] \
  || fail "Package.resolved must contain no remote source-control pins"

readonly prohibited_resolved_item="$(/usr/bin/find "$source_packages_path" \( -type f -o -type d -o -type l \) \( \
  -iname '*litert*' -o -iname '*gemma*' -o -iname '*qwen*' -o -iname '*mlx*' \
  -o -name '*.litertlm' -o -name '*.safetensors' -o -name '*.gguf' \
\) -print -quit)"
[[ -z "$prohibited_resolved_item" ]] \
  || fail "resolved source packages contain a retired AI runtime/model item: ${prohibited_resolved_item#$source_packages_path/}"

/usr/bin/python3 - "$workspace_state_path" "$project_root" <<'PY' \
  || fail "resolved workspace state is not the reviewed Apple-framework-only local package graph"
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
project_root = pathlib.Path(sys.argv[2]).resolve()
state = json.loads(state_path.read_text(encoding="utf-8"))["object"]

dependencies = state.get("dependencies", [])
artifacts = state.get("artifacts", [])
prebuilts = state.get("prebuilts", [])
if artifacts:
    raise SystemExit("unexpected SwiftPM artifact entries")
if prebuilts:
    raise SystemExit("unexpected SwiftPM prebuilt entries")
if len(dependencies) != 1:
    raise SystemExit(f"expected one local package dependency, found {len(dependencies)}")
dependency = dependencies[0]
package_ref = dependency.get("packageRef", {})
if package_ref.get("kind") != "fileSystem":
    raise SystemExit("dependency is not a file-system package")
identity = str(package_ref.get("identity", ""))
name = str(package_ref.get("name", ""))
if identity != "gi-timeline" or name != "GITimelineCore":
    raise SystemExit(f"unexpected dependency identity/name: {identity}/{name}")
location = pathlib.Path(str(package_ref.get("location", ""))).resolve()
state_path_value = pathlib.Path(str(dependency.get("state", {}).get("path", ""))).resolve()
if location != project_root or state_path_value != project_root:
    raise SystemExit("dependency does not point back to the reviewed project root")
for text in (identity, name, str(package_ref.get("location", "")), str(dependency.get("state", {}).get("path", ""))):
    lowered = text.lower()
    if any(marker in lowered for marker in ("litert", "gemma", "qwen", "mlx")):
        raise SystemExit(f"retired AI dependency marker in workspace state: {text}")
PY

print -- "RESOLVED_SOURCE_PACKAGES_VALIDATION: PASS"
print -- "package_resolved_sha256=${expected_package_resolved_sha256} remote_pins=0 artifacts=0 prebuilts=0 local_dependency=GITimelineCore runtime_payload=absent"
