import Foundation

/// The game versions this launcher is known to run. Downloads only offer
/// these, so a new Minecraft release does not break a working install.
public struct TestedVersions: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let name: String
        public let versionCode: Int

        public init(name: String, versionCode: Int) {
            self.name = name
            self.versionCode = versionCode
        }
    }

    public let versions: [Entry]

    public init(versions: [Entry]) {
        self.versions = versions
    }

    /// The copy on the main branch, so the list can grow without a new launcher.
    public static let remote = URL(string: "https://raw.githubusercontent.com/Icehunter/bedrock-launcher/main/tested-versions.json")!

    public var newest: Entry? {
        versions.max { $0.versionCode < $1.versionCode }
    }

    public func entry(code: Int) -> Entry? {
        versions.first { $0.versionCode == code }
    }

    /// True when Google Play offers a version newer than every tested one.
    public func isNewerThanTested(_ playCode: Int) -> Bool {
        guard let newest else { return false }
        return playCode > newest.versionCode
    }

    public static func decode(_ data: Data) throws -> TestedVersions {
        try JSONDecoder().decode(TestedVersions.self, from: data)
    }

    /// The fetched list when it reads, else the copy inside the app.
    public static func load(remote: Data?, bundled: Data) -> TestedVersions {
        if let remote, let list = try? decode(remote) { return list }
        return (try? decode(bundled)) ?? TestedVersions(versions: [])
    }
}
