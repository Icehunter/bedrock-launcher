import Foundation

/// Where the launcher keeps game versions, profile data, logs and settings.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/BedrockLauncher`.
    public static let standard = AppPaths(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BedrockLauncher", isDirectory: true)
    )

    public var versions: URL { root.appendingPathComponent("versions", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var profilesFile: URL { root.appendingPathComponent("profiles.json") }

    public func gameFolder(version: String) -> URL {
        versions.appendingPathComponent(version, isDirectory: true)
    }

    public func defaultDataFolder(profileID: UUID) -> URL {
        root.appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
    }
}
