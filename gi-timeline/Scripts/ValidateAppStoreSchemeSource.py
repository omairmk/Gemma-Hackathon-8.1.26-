#!/usr/bin/python3
"""Fail-closed structural validation for the shipping App Store scheme."""

from __future__ import annotations

import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    print(f"APP_STORE_SCHEME_SOURCE_VALIDATION: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


root = Path(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parent.parent)
require(
    root.is_absolute() and root.is_dir() and not root.is_symlink(),
    "source root must be an absolute non-symlink directory",
)
project_path = root / "GITimeline.xcodeproj" / "project.pbxproj"
scheme_path = (
    root
    / "GITimeline.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "GITimeline App Store.xcscheme"
)
for path in (project_path, scheme_path):
    require(
        path.is_file() and not path.is_symlink(),
        f"missing or symlinked reviewed input: {path}",
    )

try:
    project = json.loads(
        subprocess.check_output(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_path)]
        )
    )
except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
    fail(f"could not structurally parse project.pbxproj: {error}")
objects = project.get("objects", {})
targets = {
    value.get("name"): (key, value)
    for key, value in objects.items()
    if value.get("isa") == "PBXNativeTarget"
}
expected_target_types = {
    "GITimeline": "com.apple.product-type.application",
    "GITimelineTests": "com.apple.product-type.bundle.unit-test",
    "GITimelineUITests": "com.apple.product-type.bundle.ui-testing",
}
require(set(targets) == set(expected_target_types), "native-target allowlist drifted")
for name, expected_type in expected_target_types.items():
    require(
        targets[name][1].get("productType") == expected_type,
        f"{name} product type drifted",
    )

try:
    scheme = ET.parse(scheme_path).getroot()
except ET.ParseError as error:
    fail(f"could not parse App Store scheme: {error}")

prohibited_tags = {
    "AdditionalOptions",
    "CommandLineArguments",
    "EnvironmentVariables",
    "LocationScenarioReference",
    "MacroExpansion",
    "PathRunnable",
    "PostActions",
    "PreActions",
    "StoreKitConfigurationFileReference",
    "TestPlans",
}
for node in scheme.iter():
    require(node.tag not in prohibited_tags, f"scheme contains prohibited {node.tag}")


def require_reference(reference: ET.Element | None, target_name: str) -> None:
    require(reference is not None, f"scheme lacks a {target_name} buildable reference")
    if reference is None:
        return
    target_id = targets[target_name][0]
    require(reference.get("BuildableIdentifier") == "primary", f"{target_name} buildable identifier drifted")
    require(reference.get("BlueprintIdentifier") == target_id, f"{target_name} blueprint ID drifted")
    require(reference.get("BlueprintName") == target_name, f"{target_name} blueprint name drifted")
    require(
        reference.get("ReferencedContainer") == "container:GITimeline.xcodeproj",
        f"{target_name} referenced container drifted",
    )


build_action = scheme.find("./BuildAction")
require(build_action is not None, "BuildAction is missing")
if build_action is not None:
    require(build_action.get("parallelizeBuildables") == "YES", "parallel build policy drifted")
    require(build_action.get("buildImplicitDependencies") == "YES", "implicit dependency policy drifted")
build_entries = scheme.findall("./BuildAction/BuildActionEntries/BuildActionEntry")
require(len(build_entries) == 3, "BuildAction must contain exactly app, unit, and UI-test entries")
expected_build_entries = {
    "GITimeline": {
        "buildForTesting": "YES",
        "buildForRunning": "YES",
        "buildForProfiling": "YES",
        "buildForArchiving": "YES",
        "buildForAnalyzing": "YES",
    },
    "GITimelineTests": {
        "buildForTesting": "YES",
        "buildForRunning": "NO",
        "buildForProfiling": "NO",
        "buildForArchiving": "NO",
        "buildForAnalyzing": "NO",
    },
    "GITimelineUITests": {
        "buildForTesting": "YES",
        "buildForRunning": "NO",
        "buildForProfiling": "NO",
        "buildForArchiving": "NO",
        "buildForAnalyzing": "NO",
    },
}
seen_buildables: set[str] = set()
for entry in build_entries:
    reference = entry.find("./BuildableReference")
    require(reference is not None, "scheme build entry lacks a buildable reference")
    if reference is None:
        continue
    name = reference.get("BlueprintName", "")
    require(
        name in expected_build_entries and name not in seen_buildables,
        "scheme buildable allowlist drifted",
    )
    seen_buildables.add(name)
    require_reference(reference, name)
    for key, value in expected_build_entries[name].items():
        require(entry.get(key) == value, f"scheme {name} {key} drifted")
require(seen_buildables == set(expected_build_entries), "scheme buildable set drifted")

test_action = scheme.find("./TestAction")
require(test_action is not None, "TestAction is missing")
if test_action is not None:
    require(test_action.get("buildConfiguration") == "AppStoreTesting", "TestAction configuration drifted")
    require(test_action.get("shouldUseLaunchSchemeArgsEnv") == "NO", "TestAction inherits launch arguments or environment")
    require(test_action.get("shouldAutocreateTestPlan") == "YES", "TestAction test-plan policy drifted")
testables = test_action.findall("./Testables/TestableReference") if test_action is not None else []
require(len(testables) == 2, "TestAction must contain exactly unit and UI tests")
seen_testables: set[str] = set()
for testable in testables:
    require(testable.get("skipped") == "NO", "App Store scheme contains a skipped testable")
    reference = testable.find("./BuildableReference")
    require(reference is not None, "testable lacks a buildable reference")
    if reference is None:
        continue
    name = reference.get("BlueprintName", "")
    require(
        name in {"GITimelineTests", "GITimelineUITests"} and name not in seen_testables,
        "testable allowlist drifted",
    )
    seen_testables.add(name)
    require_reference(reference, name)
require(seen_testables == {"GITimelineTests", "GITimelineUITests"}, "testable set drifted")

for tag in ("LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"):
    actions = scheme.findall(f"./{tag}")
    require(len(actions) == 1, f"scheme must contain exactly one {tag}")
    require(actions[0].get("buildConfiguration") == "AppStore", f"{tag} configuration drifted")

launch_action = scheme.find("./LaunchAction")
require(launch_action is not None and launch_action.get("allowLocationSimulation") == "NO", "LaunchAction permits location simulation")
launch_reference = scheme.find("./LaunchAction/BuildableProductRunnable/BuildableReference")
require_reference(launch_reference, "GITimeline")

profile_action = scheme.find("./ProfileAction")
require(profile_action is not None and profile_action.get("shouldUseLaunchSchemeArgsEnv") == "NO", "ProfileAction inherits launch arguments or environment")
profile_reference = scheme.find("./ProfileAction/BuildableProductRunnable/BuildableReference")
require_reference(profile_reference, "GITimeline")

archive_action = scheme.find("./ArchiveAction")
require(archive_action is not None and archive_action.get("revealArchiveInOrganizer") == "NO", "ArchiveAction may reveal an unvalidated archive in Organizer")

print("APP_STORE_SCHEME_SOURCE_VALIDATION: PASS")
print("scheme_buildables=3 testables=2 test_configuration=AppStoreTesting shipping_actions=AppStore injected_args_env=false")
