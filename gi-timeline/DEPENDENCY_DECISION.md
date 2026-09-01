# LiteRT-LM dependency decision

Decision date: 2026-07-31

## Decision

Pin the official LiteRT-LM repository to exact revision
`f73637c57f0940b53da184e0d5adfc52a4e55eef`.

This is the head of the official `release/v0.14` branch at the time of this
decision. It is a direct child of the `v0.14.0` tag commit
`80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6` and changes only the two binary
checksums in `Package.swift`. The Swift wrapper and the v0.14.0 binary URLs are
otherwise identical to the tag.

This is an exact revision pin, not a floating branch or version range. It keeps
SwiftPM checksum verification enabled.

## Reproduced boundary

Command:

```sh
xcodebuild -resolvePackageDependencies \
  -project gi-timeline/GITimeline.xcodeproj \
  -scheme GITimeline \
  -clonedSourcePackagesDirPath "$PWD/work/phase0/SourcePackages" \
  -derivedDataPath "$PWD/work/phase0/DerivedData"
```

Relevant output from the unmodified `v0.14.0` project:

```text
Checking out 0.14.0 of package 'LiteRT-LM'
checksum of downloaded artifact of binary target 'CLiteRTLM_mac' (450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7) does not match checksum specified by the manifest (13e818c9d3987afa87f0716884ebf0b6b10677b480717b8b098146e6b4f45847)
checksum of downloaded artifact of binary target 'CLiteRTLM' (dddac2f6713ed65eaf01c18e115d9fec22184adf575cc7856a21387e8ba937e1) does not match checksum specified by the manifest (4a4bdb0e89689ceacc54c2fb7ae0efe8f5dad2404110976a29c3bf6b374a511e)
xcodebuild: error: Could not resolve package dependencies
```

The first sandboxed attempts failed earlier on blocked CoreDevice/SwiftPM cache
access. The command above was repeated in the approved Xcode execution context;
only that run is used to classify the dependency failure.

## Primary-source verification

Accessed 2026-07-31:

- Swift API and image-message guide:
  <https://developers.google.com/edge/litert-lm/swift>
- Official repository: <https://github.com/google-ai-edge/LiteRT-LM>
- Official v0.14.0 release:
  <https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.14.0>
- Tagged manifest:
  <https://github.com/google-ai-edge/LiteRT-LM/blob/v0.14.0/Package.swift>
- Official checksum correction:
  <https://github.com/google-ai-edge/LiteRT-LM/commit/f73637c57f0940b53da184e0d5adfc52a4e55eef>
- Merged correction PR:
  <https://github.com/google-ai-edge/LiteRT-LM/pull/2797>
- Current official checksum report:
  <https://github.com/google-ai-edge/LiteRT-LM/issues/3003>
- SwiftPM version/unsafe-flags report:
  <https://github.com/google-ai-edge/LiteRT-LM/issues/2815>
- Wrapper/binary compatibility report:
  <https://github.com/google-ai-edge/LiteRT-LM/issues/2920>

The official GitHub release API reported:

| Asset | Bytes | SHA-256 |
|---|---:|---|
| `CLiteRTLM.xcframework.zip` | 84,699,562 | `dddac2f6713ed65eaf01c18e115d9fec22184adf575cc7856a21387e8ba937e1` |
| `CLiteRTLM_mac.xcframework.zip` | 44,645,316 | `450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7` |

Local Git verification of the official repository:

```text
v0.14.0 = 80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6
f73637c parent = 80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6
v0.14.0..f73637c changed files = Package.swift only
```

A fresh consumer probe, with no `Package.resolved` and empty dependency,
configuration, security, and scratch directories, also passed:

```sh
swift package --disable-dependency-cache \
  --cache-path "$PWD/work/litert-phase0-swiftpm-fresh/cache" \
  --config-path "$PWD/work/litert-phase0-swiftpm-fresh/config" \
  --security-path "$PWD/work/litert-phase0-swiftpm-fresh/security" \
  --scratch-path "$PWD/work/litert-phase0-swiftpm-fresh/scratch" \
  resolve
```

The probe dependency was the exact `f73637c…` revision. SwiftPM fetched the
35,678-object repository, resolved the working copy at that revision, freshly
downloaded both v0.14.0 binary artifacts, and exited 0. This confirms the pin is
reconstructible without the earlier shared dependency cache.

The same fresh probe then compiled all ten Swift wrapper sources and copied the
iOS binary framework for `arm64-apple-ios15.0` against the iPhoneOS 26.5 SDK:

```sh
swift build --disable-dependency-cache \
  --cache-path "$PWD/work/litert-phase0-swiftpm-fresh/cache" \
  --config-path "$PWD/work/litert-phase0-swiftpm-fresh/config" \
  --security-path "$PWD/work/litert-phase0-swiftpm-fresh/security" \
  --scratch-path "$PWD/work/litert-phase0-swiftpm-fresh/scratch" \
  --target LiteRTLM \
  --triple arm64-apple-ios15.0 \
  --sdk "$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
```

Result: `Build of target: 'LiteRTLM' complete!`, exit 0.

The official Swift guide currently documents multimodal support, a non-nil
`visionBackend`, and image input using `Message(contents: [.imageFile(...),
.text(...)])`. The existing v0.14 wrapper also compiles its equivalent
`Message(of: ...)` form; a physical image request is still required to establish
runtime compatibility.

## Options compared

| Option | Result |
|---|---|
| Exact `v0.14.0` version | Rejected: both official binary checksums mismatch the tagged manifest. |
| Newer release/tag | Rejected for this repair: no smaller verified change preserves the already compiled v0.14 API/binaries. |
| Exact correction revision `f73637c…` | Selected: official, one-commit/two-checksum delta, exact pin, current assets verify normally. |
| Local checkout at `f73637c…` | Reserved fallback only if Xcode cannot consume the remote revision. A committed local package would require a clean reconstruction script and provenance record. |
| `main` or `release/v0.14` branch pin | Rejected: mutable and could change wrapper/binary compatibility. |

## Verification and rollback

After changing the Xcode package requirement:

1. Resolve into a clean workspace-local SourcePackages directory.
2. Confirm `Package.resolved` contains exactly `f73637c…` and no version.
3. Confirm SwiftPM reports the two expected binary digests above.
4. Run `swift test`, project/plist lint, arm64 simulator build, and app tests.
5. Do not start a physical-device install unless those checks pass.

Rollback is a normal revert of the dependency milestone commit. That restores
the prior exact-version project and its documented checksum failure; it does not
delete any app, device data, signing material, or model artifact.
