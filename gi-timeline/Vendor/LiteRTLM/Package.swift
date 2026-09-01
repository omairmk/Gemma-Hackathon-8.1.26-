// swift-tools-version: 5.9
// Copyright 2026 Google LLC
// Modified by GI Journal in 2026; see UPSTREAM_PROVENANCE.md.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
  name: "LiteRTLM",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(
      name: "LiteRTLM",
      targets: ["LiteRTLM"]
    ),
  ],
  targets: [
    // The Prebuilt Binary Target for iOS
    .binaryTarget(
      name: "CLiteRTLM",
      url:
        "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM.xcframework.zip",
      checksum: "d6ccf6b54362d894ff71a7580c7e446d36767dab908aecfbb16ffca0fa0bc59b"
    ),
    // The Prebuilt Binary Target for Mac
    .binaryTarget(
      name: "CLiteRTLM_mac",
      url:
        "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM_mac.xcframework.zip",
      checksum: "d23cf189ce8f6bb2556c0a023805e245d1ec862434e501eb60f353488033c1b5"
    ),
    // The Swift Wrapper Target
    .target(
      name: "LiteRTLM",
      dependencies: [
        .target(name: "CLiteRTLM", condition: .when(platforms: [.iOS])),
        .target(name: "CLiteRTLM_mac", condition: .when(platforms: [.macOS])),
      ],
      path: "swift"
    ),
  ]
)
