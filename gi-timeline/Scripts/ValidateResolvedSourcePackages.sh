#!/bin/zsh

set -euo pipefail

readonly source_packages_path="${1:?usage: ValidateResolvedSourcePackages.sh /absolute/path/SourcePackages}"
readonly project_root="${0:A:h:h}"
readonly vendor_root="$project_root/Vendor/LiteRTLM"
readonly workspace_state_path="$source_packages_path/workspace-state.json"
readonly package_resolved_path="$project_root/GITimeline.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
readonly expected_package_resolved_sha256="90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f"
readonly expected_wrapper_compile_input_sha256="22c81184a1bad821ea7c890c167fa0a75089ba774beaf8176a0d3b99290d842d"
readonly expected_device_binary_sha256="bced9f21e85b1aca8787709088d898b2575580d83a3b20c10020859188467840"
readonly expected_simulator_binary_sha256="d48031f8c2fbf151ba8c11fa772294364a0e6691da56fad610590856a96d8506"
readonly expected_device_binary_uuid="BD35C88F-B768-3842-B525-B3F54B900F01"
readonly expected_simulator_binary_uuid="4C4C4454-5555-3144-A103-259ECF8844DE"

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
[[ -d "$vendor_root" && ! -L "$vendor_root" ]] \
  || fail "committed LiteRT-LM wrapper root is missing or is a symlink"
[[ -f "$package_resolved_path" && ! -L "$package_resolved_path" ]] \
  || fail "Package.resolved is missing or is a symlink"
[[ -f "$workspace_state_path" && ! -L "$workspace_state_path" ]] \
  || fail "resolved workspace-state.json is missing or is a symlink"
[[ "$(sha256 "$package_resolved_path")" == "$expected_package_resolved_sha256" ]] \
  || fail "Package.resolved SHA-256 drifted"
[[ "$(/usr/bin/plutil -extract pins json -o - "$package_resolved_path")" == "[]" ]] \
  || fail "Package.resolved must contain no remote source-control pins"

/usr/bin/python3 - "$workspace_state_path" "$vendor_root" <<'PY' \
  || fail "resolved workspace state is not bound to the reviewed local wrapper and binary checksums"
import json
import pathlib
import sys

state_path = pathlib.Path(sys.argv[1])
vendor_root = pathlib.Path(sys.argv[2]).resolve()
state = json.loads(state_path.read_text(encoding="utf-8"))["object"]
dependencies = [
    item for item in state.get("dependencies", [])
    if item.get("packageRef", {}).get("identity") == "litertlm"
]
assert len(dependencies) == 1
dependency = dependencies[0]
assert dependency.get("packageRef", {}).get("kind") == "fileSystem"
assert pathlib.Path(dependency.get("packageRef", {}).get("location", "")).resolve() == vendor_root
assert dependency.get("state", {}).get("name") == "fileSystem"
assert pathlib.Path(dependency.get("state", {}).get("path", "")).resolve() == vendor_root

expected = {
    "CLiteRTLM": (
        "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM.xcframework.zip",
        "d6ccf6b54362d894ff71a7580c7e446d36767dab908aecfbb16ffca0fa0bc59b",
    ),
    "CLiteRTLM_mac": (
        "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM_mac.xcframework.zip",
        "d23cf189ce8f6bb2556c0a023805e245d1ec862434e501eb60f353488033c1b5",
    ),
}
artifacts = {
    item.get("targetName"): item
    for item in state.get("artifacts", [])
    if item.get("packageRef", {}).get("identity") == "litertlm"
}
assert set(artifacts) == set(expected)
for target, (url, checksum) in expected.items():
    artifact = artifacts[target]
    assert artifact.get("packageRef", {}).get("kind") == "fileSystem"
    assert pathlib.Path(artifact.get("packageRef", {}).get("location", "")).resolve() == vendor_root
    assert artifact.get("source", {}).get("type") == "remote"
    assert artifact.get("source", {}).get("url") == url
    assert artifact.get("source", {}).get("checksum") == checksum
PY

typeset -a expected_files
expected_files=(
  LICENSE
  Package.swift
  UPSTREAM_PROVENANCE.md
  swift/Benchmark.swift
  swift/Capabilities.swift
  swift/Config.swift
  swift/Conversation.swift
  swift/Engine.swift
  swift/ExperimentalFlags.swift
  swift/LiteRTLMError.swift
  swift/Message.swift
  swift/ResponseFormat.swift
  swift/Tool.swift
  swift/ToolManager.swift
)

typeset -A expected_hashes
expected_hashes=(
  LICENSE c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4
  Package.swift 2b0198141da34376a445942a3e93ca0a4eb9f16c811d3d342ac3d3d4947d4428
  UPSTREAM_PROVENANCE.md 5ae7140e0228f2c7f1cf51701d0a442036969819deaff4e59a8d93779e70b155
  swift/Benchmark.swift 9096200cb1ad930cb6ac9af72747c430621739838b9f18ec8d3b2ea4fce7fd74
  swift/Capabilities.swift 30bc7cd1057f9100ef19249863266481a61e4c80d2a28ccb6098236318dee020
  swift/Config.swift 721289dc0bc213c2371119eaf49e24b6d5324572990c6ac2a9de1926423731da
  swift/Conversation.swift 49701ac6c3856bb921e191a260fb19e58ec49b2f057a211093796dffc22e6b9e
  swift/Engine.swift 098853a2a0ba79ed2b3ced53799178b86579619c0de8a3b67e7006239325514b
  swift/ExperimentalFlags.swift e7aa8ed306d0ab5c84557512da020a140af4c7b90c4d8cb54a53f585182fdbfc
  swift/LiteRTLMError.swift 35226ebc4ba514db9f886bc2153ba3de93e9a500d3f4c2946a87f177069441b2
  swift/Message.swift 23631912d2caf0a63f971e5da869ef9e385fa1b93e459e1ea3232cc6a99fa637
  swift/ResponseFormat.swift 071705a8d9e9916a83b2197514d58bdbd3a30e643903a9e826a500fb67772067
  swift/Tool.swift d9698c6c7f8425cfa1f479cec5070fe94d9ca732b3e20b171e3dd90ca1545422
  swift/ToolManager.swift 7fed45d66e562a153dd61e57a8cc67cbd89fa063d1c09d9d20626ea48574d3f7
)

[[ -z "$(/usr/bin/find "$vendor_root" -type l -print -quit)" ]] \
  || fail "vendored wrapper contains a symlink"
# Xcode's per-user scheme ordering is not a build input; exclude only this exact generated shape.
readonly actual_file_count="$(/usr/bin/find "$vendor_root" -type f \
  ! -path "$vendor_root/.swiftpm/xcode/xcuserdata/*.xcuserdatad/xcschemes/xcschememanagement.plist" \
  | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
[[ "$actual_file_count" == "${#expected_files[@]}" ]] \
  || fail "vendored wrapper file allowlist drifted: found ${actual_file_count}, expected ${#expected_files[@]}"
for relative_path in "${expected_files[@]}"; do
  absolute_path="$vendor_root/$relative_path"
  [[ -f "$absolute_path" && ! -L "$absolute_path" ]] \
    || fail "vendored wrapper file is missing, non-regular, or a symlink: ${relative_path}"
  [[ "$(sha256 "$absolute_path")" == "${expected_hashes[$relative_path]}" ]] \
    || fail "vendored wrapper bytes drifted: ${relative_path}"
done

readonly compile_input_sha256="$(
  /usr/bin/shasum -a 256 \
    "$vendor_root/Package.swift" \
    "$vendor_root/swift/Benchmark.swift" \
    "$vendor_root/swift/Capabilities.swift" \
    "$vendor_root/swift/Config.swift" \
    "$vendor_root/swift/Conversation.swift" \
    "$vendor_root/swift/Engine.swift" \
    "$vendor_root/swift/ExperimentalFlags.swift" \
    "$vendor_root/swift/LiteRTLMError.swift" \
    "$vendor_root/swift/Message.swift" \
    "$vendor_root/swift/ResponseFormat.swift" \
    "$vendor_root/swift/Tool.swift" \
    "$vendor_root/swift/ToolManager.swift" \
    | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
)"
[[ "$compile_input_sha256" == "$expected_wrapper_compile_input_sha256" ]] \
  || fail "vendored wrapper compile-input identity drifted"

/usr/bin/grep -Fq \
  'https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM.xcframework.zip' \
  "$vendor_root/Package.swift" \
  || fail "official v0.15.0 iOS binary URL drifted"
/usr/bin/grep -Fq \
  'd6ccf6b54362d894ff71a7580c7e446d36767dab908aecfbb16ffca0fa0bc59b' \
  "$vendor_root/Package.swift" \
  || fail "official v0.15.0 iOS binary checksum drifted"
/usr/bin/grep -Fq 'litert_lm_engine_settings_set_max_num_images(settings' \
  "$vendor_root/swift/Engine.swift" \
  || fail "vendored wrapper no longer forwards explicit image capacity"
/usr/bin/grep -Fq 'litert_lm_engine_settings_set_num_threads(settings' \
  "$vendor_root/swift/Engine.swift" \
  || fail "vendored wrapper no longer forwards explicit main CPU thread count"

typeset -a artifact_info_candidates
artifact_info_candidates=(
  "$source_packages_path"/artifacts/*/CLiteRTLM/CLiteRTLM.xcframework/Info.plist(N)
)
[[ ${#artifact_info_candidates[@]} == 1 ]] \
  || fail "expected exactly one resolved CLiteRTLM iOS xcframework artifact"
readonly xcframework_root="${artifact_info_candidates[1]:h}"
typeset -a binaries
binaries=(
  "$xcframework_root/ios-arm64/CLiteRTLM.framework/CLiteRTLM"
  "$xcframework_root/ios-arm64-simulator/CLiteRTLM.framework/CLiteRTLM"
)
for binary in "${binaries[@]}"; do
  [[ -f "$binary" && ! -L "$binary" ]] \
    || fail "resolved CLiteRTLM binary is missing, non-regular, or a symlink"
  binary_symbols="$(/usr/bin/nm -gj "$binary")" \
    || fail "could not inspect resolved CLiteRTLM symbols"
  [[ "$binary_symbols" == *'_litert_lm_engine_settings_set_max_num_images'* ]] \
    || fail "resolved CLiteRTLM binary lacks the image-capacity setter"
  [[ "$binary_symbols" == *'_litert_lm_engine_settings_set_num_threads'* ]] \
    || fail "resolved CLiteRTLM binary lacks the CPU-thread setter"
done
[[ "$(/usr/bin/lipo -archs "${binaries[1]}")" == "arm64" ]] \
  || fail "resolved device CLiteRTLM binary architecture drifted"
[[ "$(/usr/bin/lipo -archs "${binaries[2]}")" == "arm64" ]] \
  || fail "resolved Simulator CLiteRTLM binary architecture drifted"
[[ "$(sha256 "${binaries[1]}")" == "$expected_device_binary_sha256" ]] \
  || fail "resolved device CLiteRTLM bytes are not the reviewed v0.15.0 artifact"
[[ "$(sha256 "${binaries[2]}")" == "$expected_simulator_binary_sha256" ]] \
  || fail "resolved Simulator CLiteRTLM bytes are not the reviewed v0.15.0 artifact"
[[ "$(/usr/bin/dwarfdump --uuid "${binaries[1]}")" == "UUID: ${expected_device_binary_uuid} (arm64) ${binaries[1]}" ]] \
  || fail "resolved device CLiteRTLM UUID drifted"
[[ "$(/usr/bin/dwarfdump --uuid "${binaries[2]}")" == "UUID: ${expected_simulator_binary_uuid} (arm64) ${binaries[2]}" ]] \
  || fail "resolved Simulator CLiteRTLM UUID drifted"

print -- "RESOLVED_SOURCE_PACKAGES_VALIDATION: PASS"
print -- "litert_upstream_revision=2117fc4314670e00047bc8469783f02a68c33f0c wrapper_compile_input_sha256=${compile_input_sha256} package_resolved_sha256=${expected_package_resolved_sha256} source_mode=reviewed-local-wrapper binary_checksum_pinned=true exact_v015_binary_hashes=true native_setters_verified=true"
