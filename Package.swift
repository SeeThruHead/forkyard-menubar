// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ForkyardBar",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "ForkyardBar", path: "Sources/ForkyardBar")
  ]
)
