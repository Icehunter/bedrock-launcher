// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BedrockLauncher",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BedrockLauncher", targets: ["BedrockLauncher"]),
        .executable(name: "mcpelauncher-webview", targets: ["mcpelauncher-webview"]),
    ],
    targets: [
        .target(name: "BedrockLauncherCore"),
        .executableTarget(
            name: "BedrockLauncher",
            dependencies: ["BedrockLauncherCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "mcpelauncher-webview", dependencies: ["BedrockLauncherCore"]),
        .testTarget(name: "BedrockLauncherCoreTests", dependencies: ["BedrockLauncherCore"]),
    ]
)
