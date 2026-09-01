// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GITimelineCore",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [
    .library(name: "GITimelineCore", targets: ["GITimelineCore"]),
    .executable(name: "Qwen3HostEvidenceFuse", targets: ["Qwen3HostEvidenceFuse"]),
  ],
  targets: [
    .target(name: "GITimelineCore"),
    .executableTarget(
      name: "Qwen3HostEvidenceFuse",
      dependencies: ["GITimelineCore"],
      path: "Tools/Qwen3HostEvidenceFuse"
    ),
    .testTarget(name: "GITimelineCoreTests", dependencies: ["GITimelineCore"]),
  ]
)
