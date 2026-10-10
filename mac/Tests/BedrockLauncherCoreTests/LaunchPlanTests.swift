import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct LaunchPlanTests {
    let contents = URL(fileURLWithPath: "/Applications/Bedrock Launcher.app/Contents")
    let game = URL(fileURLWithPath: "/data/versions/1.26.52.3")
    let data = URL(fileURLWithPath: "/data/profile")

    func plan(window: (width: Int, height: Int)? = nil, extra: [String] = [], debug: Bool = false,
              game: URL? = nil, base: [String: String] = ["PATH": "/usr/bin:/bin"]) -> LaunchPlan {
        LaunchPlan.make(contents: contents, gameFolder: game ?? self.game, dataFolder: data,
                        windowSize: window, extraArguments: extra, networkDebug: debug, baseEnvironment: base)
    }

    @Test func makesRunBundleArguments() {
        let p = plan()
        #expect(p.executable.path == "/Applications/Bedrock Launcher.app/Contents/MacOS/mcpelauncher-client")
        #expect(p.arguments == [
            "-dg", "/data/versions/1.26.52.3",
            "-dd", "/data/profile",
            "-dc", "/data/profile/cache",
            "-m", "/Applications/Bedrock Launcher.app/Contents/Resources/mods/mcpelauncher-updates",
        ])
    }

    @Test func setsDataDirsAndPath() {
        let p = plan()
        #expect(p.environment["XDG_DATA_DIRS"] == "/Applications/Bedrock Launcher.app/Contents/Resources")
        #expect(p.environment["PATH"] == "/Applications/Bedrock Launcher.app/Contents/MacOS:/usr/bin:/bin")
    }

    @Test func standardizesRelativeAndSpacedPaths() {
        let p = plan(game: URL(fileURLWithPath: "rel/../rel/My Game"))
        let dg = p.arguments[1]
        #expect(dg.hasPrefix("/"))
        #expect(dg.hasSuffix("/rel/My Game"))
        #expect(!dg.contains(".."))
    }

    @Test func addsWindowSizeBeforeExtraArguments() {
        let p = plan(window: (1280, 720), extra: ["-ifp", "/tmp/a.mcpack"])
        #expect(Array(p.arguments.suffix(6)) == ["-ww", "1280", "-wh", "720", "-ifp", "/tmp/a.mcpack"])
    }

    @Test func networkDebugSetsShimVariable() {
        #expect(plan(debug: true).environment["SHIM_NETDBG"] == "1")
        #expect(plan(debug: false).environment["SHIM_NETDBG"] == nil)
    }
}
