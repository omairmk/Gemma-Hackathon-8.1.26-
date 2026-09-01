# GI Journal software bill of materials

Status: **human-readable draft for the manual-fallback AppStore candidate; not a final signed SBOM**.
Updated: 2026-09-01.

This SBOM describes the current public AppStore lane in this branch. Historical Gemma, Qwen, LiteRT, MLX, raw-photo, and synthetic-evaluation materials are not current public runtime dependencies and must not be treated as shipped components.

## Release identity

| Field | Value |
|---|---|
| Product | GI Journal |
| Bundle identifier | `com.omairmkhan.GITimeline` |
| Platform | iPhone / iOS 17.0 or later |
| Marketing version | `1.0` in the current project; confirm before submission |
| Build number | `8` in the current project; confirm before submission |
| Source commit | **[FINAL GIT COMMIT]** |
| Source tree | **[FINAL GIT TREE]** |
| Xcode / Swift toolchain | **[FINAL XCODE BUILD AND SWIFT VERSION]** |
| Signed archive / IPA hashes | **[FINAL ARCHIVE AND IPA IDENTIFIERS]** |
| Release operator | **[RELEASE OPERATOR]** |

## First-party components

| Component | Type | Source | License/status |
|---|---|---|---|
| GI Journal iOS application | Swift application | This repository at the final source commit | **[FIRST-PARTY LICENSE / PROPRIETARY NOTICE — LEGAL CONFIRM]** |
| GITimelineCore | Local Swift package | `Package.swift`, `Sources/GITimelineCore` | Same first-party terms |
| Release scripts and validation tooling | Shell/Python tooling | `Scripts/` | Internal release engineering materials; not bundled in the app |

## Apple platform dependencies

The app imports Apple-provided SDK/OS frameworks for user interface, data persistence, camera/photo attachment, PDF generation, image handling, file handling, and cryptographic hashes. Observed source imports include SwiftUI, SwiftData, Foundation, UIKit, PhotosUI, PDFKit, ImageIO, CoreGraphics, CoreText, CryptoKit, UniformTypeIdentifiers, and Darwin. These are supplied by Apple rather than vendored application packages.

Record the exact SDK, Xcode, Swift, and deployment-target evidence from the final signed archive.

## Third-party runtime and model payload status

Current public AppStore lane:

- No LiteRT package product is linked.
- No `CLiteRTLM.framework` is embedded.
- No Gemma, Qwen, MLX, `.litertlm`, `.safetensors`, `.gguf`, or `EmbeddedModels` payload is bundled.
- `Package.resolved` has SHA-256 `90798d0becbb33b4f42aa0e8ea7bd7a8cc2a8c752fc94417b6fd6b2f7b844a8f` and contains no remote source-control pins.
- The resolved package graph has one local file-system dependency: `GITimelineCore`.

Historical AI/model ledgers may remain in nonshipping history or excluded work areas, but they are not current public runtime dependencies. If a future AI-enabled candidate is admitted, regenerate this SBOM from that exact branch, artifact, and legal review instead of extending this manual-fallback SBOM.

## Bundled resources expected in the public app

| Resource | Public AppStore disposition |
|---|---|
| `GITimeline` executable | Required |
| `Info.plist` | Required; production bundle ID, version/build, public URLs, and source binding must match the release record |
| `PrivacyInfo.xcprivacy` | Required and validated |
| `Assets.car` and app icon PNGs | Required |
| `ThirdPartyNotices.txt` | Required; currently states that no third-party model or inference runtime is bundled |
| `PkgInfo` | Allowed by the bundle format |
| `embedded.mobileprovision` and `_CodeSignature` | Present only in signed archive/IPA flows |
| `EmbeddedModels`, model receipts, `.litertlm`, `.safetensors`, `.gguf`, LiteRT, Gemma, Qwen, MLX payloads | Prohibited |
| Debug/Hackathon/QA fixtures, evaluation manifests, synthetic image sets, XCTest payloads | Prohibited in production archive/IPA |

## Current non-device evidence

- AppStoreTesting package validator measured `24,996,417` uncompressed regular-file bytes with a `725,003,583`-byte local margin beneath the validator ceiling.
- The validator checked platform, Info.plist, privacy manifest, app icon, closed bundle file set, dependency dump, prohibited payload names, prohibited launch markers, and retired recovery markers.
- The resolver validator checked zero remote pins, zero artifacts, zero prebuilts, and one local `GITimelineCore` dependency.

This is not a final archive/IPA SBOM, upload receipt, Apple-processed size receipt, legal approval, or physical-device result.

## Final-generation procedure

1. Freeze a final source commit and record its commit and tree.
2. Build and archive the production `AppStore` configuration with approved public HTTPS privacy/support URLs.
3. Validate the signed archive and exported IPA with the release validators in `Scripts/`.
4. Generate machine-readable SPDX or CycloneDX output from the exact signed artifact.
5. Reconcile this human-readable draft with the machine-readable SBOM, final bundle inventory, privacy manifest, dependency graph, and legal review.
6. Retain the signed release record with hashes, UUIDs, tool versions, archive path, IPA path, and upload receipt.

## Approval status

- **[RELEASE ENGINEERING — BLOCKING]** Final archive/IPA inventory and machine-readable SBOM.
- **[LEGAL — BLOCKING]** First-party license/copyright notice and release wording.
- **[SECURITY/PRIVACY — BLOCKING]** Exact signed-artifact privacy, network, and dependency review.
