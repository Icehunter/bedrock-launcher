// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BedrockLauncher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BedrockLauncher", path: "Sources/BedrockLauncher")
    ]
)
