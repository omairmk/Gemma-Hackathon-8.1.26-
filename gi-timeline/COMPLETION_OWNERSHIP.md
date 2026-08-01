# GI Timeline completion ownership

Live first-wave ownership for the multi-model completion steering run on 2026-08-01. All paths are relative to `gi-timeline/` unless noted.

## Lead / integrator

- `GITimeline.xcodeproj/project.pbxproj`
- `GITimeline.xcodeproj/xcshareddata/xcschemes/`
- `Scripts/EmbedGemmaE4B.sh`
- `GITimeline/GITimelineApp.swift`
- `GITimeline/NewEntryViewModel.swift`
- cross-cutting interfaces, signing, physical install/launch, evidence integration, Git, and final status

## Agent 1 / Gemma runtime

- `GITimeline/ModelImporter.swift`
- `GITimeline/ModelRuntime.swift`
- `GITimeline/InferenceService.swift`
- `GITimeline/DeviceInferenceLab.swift`
- runtime-focused additions inside `GITimelineTests/GITimelineTests.swift`

Agent 1 must not edit UI, project/scheme, signing, evidence, or Git files. Cross-owned changes are proposed to the lead.

## Agent 2 / iOS product UI

- `GITimeline/NewEntryView.swift`
- `GITimeline/HistoryView.swift`
- `GITimeline/Info.plist`
- `GITimelineUITests/GITimelineUITests.swift`

Agent 2 must not edit runtime, persistence, project/scheme, signing, evidence, or Git files. Cross-owned changes are proposed to the lead.

## Agent 3 / device QA

- Read-only across the repository and device by default.
- May write only a new dedicated report at `QA_COMPLETION_AUDIT.md` if useful.
- Must not edit production code, tests owned above, project/scheme, signing, Git state, or model files.

## Shared protocol

- Preserve the dirty worktree; never reset, revert, clean, or overwrite existing work.
- Inspect the live diff before edits.
- Use distinct DerivedData directories and do not run overlapping device builds.
- Never print or commit signing values, device identifiers, credentials, private logs, DerivedData, test result bundles, or model weights.
- Report inspected/changed files, exact command, PASS/FAIL/BLOCKED, evidence path, and next action.
