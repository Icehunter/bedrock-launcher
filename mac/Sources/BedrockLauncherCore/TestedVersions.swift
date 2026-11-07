import Foundation

/// The game versions the launcher offers to download. Each entry is marked
/// tested or untested; untested ones are offered too, with a warning. Only
/// tested ones count as "newest" for the Google Play banner.
public struct TestedVersions: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let name: String
        public let versionCode: Int
        public let tested: Bool

        public init(name: String, versionCode: Int, tested: Bool = true) {
            self.name = name
            self.versionCode = versionCode
            self.tested = tested
        }

        /// Entries written before the flag existed count as tested.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            versionCode = try c.decode(Int.self, forKey: .versionCode)
            tested = try c.decodeIfPresent(Bool.self, forKey: .tested) ?? true
        }
    }

    public let versions: [Entry]

    public init(versions: [Entry]) {
        self.versions = versions
    }

    /// The copy on the main branch, so the list can grow without a new launcher.
    public static let remote = URL(string: "https://raw.githubusercontent.com/Icehunter/bedrock-launcher/main/tested-versions.json")!

    public var testedVersions: [Entry] {
        versions.filter(\.tested)
    }

    /// The newest entry marked tested.
    public var newest: Entry? {
        testedVersions.max { $0.versionCode < $1.versionCode }
    }

    public func entry(code: Int) -> Entry? {
        versions.first { $0.versionCode == code }
    }

    /// True when Google Play offers a version newer than every tested one.
    public func isNewerThanTested(_ playCode: Int) -> Bool {
        guard let newest else { return false }
        return playCode > newest.versionCode
    }

    /// The list plus Google Play's current version when the list lacks it, as
    /// an untested entry, so a release nobody has listed yet can still be tried.
    public func including(playCode: Int?) -> TestedVersions {
        guard let playCode, entry(code: playCode) == nil else { return self }
        let name = Self.guessName(code: playCode) ?? "build \(playCode)"
        return TestedVersions(versions: versions + [Entry(name: name, versionCode: playCode, tested: false)])
    }

    /// 972606004 reads as 1.26.60.4: "97", minor, three-digit patch, two-digit build.
    /// Only a label; the installed version's name comes from its manifest.
    static func guessName(code: Int) -> String? {
        let s = String(code)
        guard s.count == 9, s.hasPrefix("97"),
              let minor = Int(s.dropFirst(2).prefix(2)),
              let patch = Int(s.dropFirst(4).prefix(3)),
              let build = Int(s.suffix(2)) else { return nil }
        return "1.\(minor).\(patch).\(build)"
    }

    public static func decode(_ data: Data) throws -> TestedVersions {
        try JSONDecoder().decode(TestedVersions.self, from: data)
    }

    /// The fetched list, plus any entry only the copy inside the app has. The
    /// fetched copy wins on a code both lists hold.
    public static func load(remote: Data?, bundled: Data) -> TestedVersions {
        let local = (try? decode(bundled))?.versions ?? []
        guard let remote, let fetched = try? decode(remote) else { return TestedVersions(versions: local) }
        let known = Set(fetched.versions.map(\.versionCode))
        return TestedVersions(versions: fetched.versions + local.filter { !known.contains($0.versionCode) })
    }
}
