#!/usr/bin/python3
"""Fail-closed structural validation for the nonshipping physical-QA lane."""

from __future__ import annotations

import json
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def fail(message: str) -> "NoReturn":
    print(f"PHYSICAL_QUALIFICATION_SOURCE_VALIDATION: FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


root = Path(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parent.parent)
require(root.is_absolute() and root.is_dir() and not root.is_symlink(), "source root must be an absolute non-symlink directory")
project_path = root / "GITimeline.xcodeproj" / "project.pbxproj"
scheme_path = root / "GITimeline.xcodeproj" / "xcshareddata" / "xcschemes" / "GITimeline Physical Qualification.xcscheme"
ui_source_path = root / "GITimelineUITests" / "GITimelineUITests.swift"
for path in (project_path, scheme_path, ui_source_path):
    require(path.is_file() and not path.is_symlink(), f"missing or symlinked reviewed input: {path}")

try:
    project = json.loads(subprocess.check_output([
        "/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_path)
    ]))
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
    require(targets[name][1].get("productType") == expected_type, f"{name} product type drifted")


def configuration(target: dict, name: str) -> dict:
    config_list = objects.get(target.get("buildConfigurationList"), {})
    matches = [
        objects.get(config_id, {})
        for config_id in config_list.get("buildConfigurations", [])
        if objects.get(config_id, {}).get("name") == name
    ]
    require(len(matches) == 1, f"target {target.get('name')} must have exactly one {name} configuration")
    return matches[0].get("buildSettings", {})


app_id, app = targets["GITimeline"]
unit_id, _unit = targets["GITimelineTests"]
ui_id, ui = targets["GITimelineUITests"]
app_qa = configuration(app, "PhysicalQualification")
ui_qa = configuration(ui, "PhysicalQualification")

expected_app_settings = {
    "APPSTORE_VALIDATION_ENABLED": "YES",
    "APP_DISPLAY_NAME": "GI Journal QA",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "8",
    "ENABLE_DEBUG_DYLIB": "NO",
    "ENABLE_TESTABILITY": "NO",
    "GEMMA_EMBED_ENABLED": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "GI_PRIVACY_POLICY_URL": "https://example.invalid/gi-journal/physical-qualification/privacy-policy",
    "GI_SOURCE_COMMIT": "PHYSICAL_QUALIFICATION_SOURCE_COMMIT_REQUIRED",
    "GI_SOURCE_TREE": "PHYSICAL_QUALIFICATION_SOURCE_TREE_REQUIRED",
    "GI_SUPPORT_URL": "https://example.invalid/gi-journal/physical-qualification/support",
    "INFOPLIST_FILE": "GITimeline/Info-AppStore.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LITERT_PRIVACY_INJECTION_ENABLED": "YES",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.omairmkhan.GITimeline.qualification",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "APPSTORE_RELEASE",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "TARGETED_DEVICE_FAMILY": "1",
    "VALIDATE_PRODUCT": "YES",
}
for key, value in expected_app_settings.items():
    require(str(app_qa.get(key)) == value, f"app PhysicalQualification {key} drifted")
require(
    set(app_qa.get("EXCLUDED_SOURCE_FILE_NAMES", []))
    == {
        "synthetic-brown-clay.svg.png",
        "synthetic-green-clay.svg.png",
        "synthetic-control-geometric.svg.png",
    },
    "app PhysicalQualification synthetic-resource exclusion drifted",
)

expected_ui_settings = {
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.omairmkhan.GITimeline.qualification.uitests",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "APPSTORE_RELEASE_TESTING",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_TARGET_NAME": "GITimeline",
}
for key, value in expected_ui_settings.items():
    require(str(ui_qa.get(key)) == value, f"UI-test PhysicalQualification {key} drifted")

prohibited_setting_fragments = (
    "ENTITLEMENT", "ICLOUD", "UBIQUITY", "KEYCHAIN", "APP_GROUP",
    "ASSOCIATED_DOMAINS", "PUSH", "HEALTHKIT", "SYSTEMCAPABILITIES",
)
for object_id, value in objects.items():
    if value.get("isa") != "XCBuildConfiguration":
        continue
    for key in value.get("buildSettings", {}):
        normalized = key.upper().replace("-", "_")
        require(
            not any(fragment in normalized for fragment in prohibited_setting_fragments),
            f"unreviewed capability setting {key} in {object_id}",
        )

require(ui.get("packageProductDependencies") == [], "UI-test target gained a package dependency")
require(len(ui.get("dependencies", [])) == 1, "UI-test target must have exactly one app dependency")
dependency = objects.get(ui["dependencies"][0], {})
require(dependency.get("target") == app_id, "UI-test target dependency no longer points to the app")

ui_phases = [objects.get(phase_id, {}) for phase_id in ui.get("buildPhases", [])]
require(
    [phase.get("isa") for phase in ui_phases]
    == ["PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"],
    "UI-test build-phase allowlist or order drifted",
)
source_files = ui_phases[0].get("files", [])
require(len(source_files) == 1, "UI-test target must compile exactly one source file")
source_build_file = objects.get(source_files[0], {})
source_reference = objects.get(source_build_file.get("fileRef"), {})
require(source_reference.get("path") == "GITimelineUITests.swift", "UI-test source allowlist drifted")
require(ui_phases[1].get("files", []) == [], "UI-test target gained a framework build file")
require(ui_phases[2].get("files", []) == [], "UI-test target gained a resource")

local_packages = {
    value.get("relativePath")
    for value in objects.values()
    if value.get("isa") == "XCLocalSwiftPackageReference"
}
require(local_packages == {".", "Vendor/LiteRTLM"}, "local package-reference allowlist drifted")
require(
    not any(value.get("isa") == "XCRemoteSwiftPackageReference" for value in objects.values()),
    "remote Swift package reference remains in the project",
)

try:
    scheme = ET.parse(scheme_path).getroot()
except ET.ParseError as error:
    fail(f"could not parse physical-qualification scheme: {error}")

prohibited_tags = {
    "CommandLineArguments", "EnvironmentVariables", "TestPlans",
    "AdditionalOptions", "MacroExpansion", "StoreKitConfigurationFileReference",
}
for node in scheme.iter():
    require(node.tag not in prohibited_tags, f"scheme contains prohibited {node.tag}")

build_entries = scheme.findall("./BuildAction/BuildActionEntries/BuildActionEntry")
require(len(build_entries) == 2, "scheme BuildAction must contain exactly app and UI tests")
expected_build_entries = {
    "GITimeline": {
        "buildForTesting": "YES", "buildForRunning": "YES",
        "buildForProfiling": "YES", "buildForArchiving": "NO",
        "buildForAnalyzing": "YES",
    },
    "GITimelineUITests": {
        "buildForTesting": "YES", "buildForRunning": "NO",
        "buildForProfiling": "NO", "buildForArchiving": "NO",
        "buildForAnalyzing": "NO",
    },
}
seen_buildables: set[str] = set()
for entry in build_entries:
    reference = entry.find("./BuildableReference")
    require(reference is not None, "scheme build entry lacks a buildable reference")
    name = reference.get("BlueprintName", "")
    require(name in expected_build_entries and name not in seen_buildables, "scheme buildable allowlist drifted")
    seen_buildables.add(name)
    for key, value in expected_build_entries[name].items():
        require(entry.get(key) == value, f"scheme {name} {key} drifted")
    expected_id = app_id if name == "GITimeline" else ui_id
    require(reference.get("BlueprintIdentifier") == expected_id, f"scheme {name} blueprint ID drifted")
require(seen_buildables == set(expected_build_entries), "scheme buildable set drifted")

test_action = scheme.find("./TestAction")
require(test_action is not None, "scheme TestAction is missing")
require(test_action.get("buildConfiguration") == "PhysicalQualification", "TestAction configuration drifted")
require(test_action.get("shouldUseLaunchSchemeArgsEnv") == "NO", "TestAction inherits launch arguments or environment")
testables = test_action.findall("./Testables/TestableReference")
require(len(testables) == 1 and testables[0].get("skipped") == "NO", "scheme must run exactly one non-skipped UI testable")
test_reference = testables[0].find("./BuildableReference")
require(
    test_reference is not None
    and test_reference.get("BlueprintName") == "GITimelineUITests"
    and test_reference.get("BlueprintIdentifier") == ui_id,
    "scheme TestAction is not bound exactly to GITimelineUITests",
)

for tag in ("LaunchAction", "ProfileAction", "AnalyzeAction", "ArchiveAction"):
    action = scheme.find(f"./{tag}")
    require(action is not None and action.get("buildConfiguration") == "PhysicalQualification", f"{tag} configuration drifted")
launch_action = scheme.find("./LaunchAction")
require(launch_action is not None and launch_action.get("allowLocationSimulation") == "NO", "qualification LaunchAction permits location simulation")
profile_action = scheme.find("./ProfileAction")
require(profile_action is not None and profile_action.get("shouldUseLaunchSchemeArgsEnv") == "NO", "ProfileAction inherits launch arguments or environment")
archive_action = scheme.find("./ArchiveAction")
require(archive_action is not None and archive_action.get("revealArchiveInOrganizer") == "NO", "qualification archive may appear in Organizer")

ui_source = ui_source_path.read_text(encoding="utf-8")
marker = "#elseif APPSTORE_RELEASE_TESTING"
require(ui_source.count(marker) == 1, "public UI-test compilation branch drifted")
public_branch = ui_source.split(marker, 1)[1]
require(
    public_branch.count("func testPublicFirstRunAndManualRouteAreReachableWithoutTestHooks()") == 1,
    "approved public physical UI test is missing or duplicated",
)
for prohibited in (
    "--ui-test-fake-gemma", "--ui-test-ephemeral-store", "--ui-test-seed-journal",
    "--internal-app-store-raw-image", "launchEnvironment", "UIPasteboard",
):
    require(prohibited not in public_branch, f"public physical UI branch contains prohibited hook {prohibited}")

print("PHYSICAL_QUALIFICATION_SOURCE_VALIDATION: PASS")
print("targets=3 scheme_buildables=2 testables=1 configuration=PhysicalQualification public_ui_hooks=false local_litert_wrapper=true")
