import Foundation

/// The command and environment that start the game from a client bundle.
/// Matches scripts/run-bundle.sh.
public struct LaunchPlan: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]

    /// - Parameters:
    ///   - contents: the bundle's `Contents` folder.
    ///   - gameFolder: the unpacked game version.
    ///   - dataFolder: worlds, settings and the saved Xbox sign-in.
    ///   - baseEnvironment: the environment to start from, usually the launcher's own.
    public static func make(
        contents: URL,
        gameFolder: URL,
        dataFolder: URL,
        windowSize: (width: Int, height: Int)?,
        extraArguments: [String],
        networkDebug: Bool,
        baseEnvironment: [String: String]
    ) -> LaunchPlan {
        // The game needs full paths. A relative data folder is resolved against
        // the game's assets, and the saved sign-in is then not found.
        let contents = contents.standardizedFileURL
        let game = gameFolder.standardizedFileURL.path
        let data = dataFolder.standardizedFileURL.path

        var arguments = [
            "-dg", game,
            "-dd", data,
            "-dc", data + "/cache",
            "-m", contents.appendingPathComponent("Resources/mods/mcpelauncher-updates").path,
        ]
        if let size = windowSize {
            arguments += ["-ww", String(size.width), "-wh", String(size.height)]
        }
        arguments += extraArguments

        var environment = baseEnvironment
        let macOS = contents.appendingPathComponent("MacOS").path
        environment["PATH"] = [macOS, baseEnvironment["PATH"]].compactMap { $0 }.joined(separator: ":")
        environment["XDG_DATA_DIRS"] = contents.appendingPathComponent("Resources").path
        if networkDebug {
            environment["SHIM_NETDBG"] = "1"
        } else {
            environment.removeValue(forKey: "SHIM_NETDBG")
        }

        return LaunchPlan(
            executable: contents.appendingPathComponent("MacOS/mcpelauncher-client"),
            arguments: arguments,
            environment: environment
        )
    }
}
