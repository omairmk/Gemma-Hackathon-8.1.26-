// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "GITimelineCore",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "GITimelineCore", targets: ["GITimelineCore"])],
  targets: [
    .target(name: "GITimelineCore"),
    .testTarget(name: "GITimelineCoreTests", dependencies: ["GITimelineCore"]),
  ]
)
