import Foundation

/// Launcher options shown on the Settings page.
public struct LauncherSettings: Codable, Equatable, Sendable {
    public var hideWhilePlaying = true
    public var checkForUpdates = true
    public var keepDownloadedAPKs = false
    public var networkDebug = false

    public init() {}

    static let key = "launcherSettings"

    public static func load(from defaults: UserDefaults = .standard) -> LauncherSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(LauncherSettings.self, from: data)
        else { return LauncherSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
