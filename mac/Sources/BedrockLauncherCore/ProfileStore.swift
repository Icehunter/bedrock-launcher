import Foundation

public enum ProfileStoreError: Error, Equatable {
    case lastProfile
}

/// Profiles and the selected one, kept in a JSON file.
public final class ProfileStore {
    private struct Stored: Codable {
        var profiles: [Profile]
        var selectedID: UUID
    }

    public let file: URL
    public private(set) var profiles: [Profile]
    public var selectedID: UUID

    /// Reads `file`, or starts with one profile named Default when it does not exist.
    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: file))
            profiles = stored.profiles.isEmpty ? [Profile(name: "Default")] : stored.profiles
            selectedID = profiles.contains { $0.id == stored.selectedID } ? stored.selectedID : profiles[0].id
        } else {
            let first = Profile(name: "Default")
            profiles = [first]
            selectedID = first.id
        }
    }

    public var selected: Profile {
        profiles.first { $0.id == selectedID } ?? profiles[0]
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Stored(profiles: profiles, selectedID: selectedID)).write(to: file, options: .atomic)
    }

    public func add(_ profile: Profile) {
        profiles.append(profile)
    }

    public func update(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        }
    }

    public func remove(id: UUID) throws {
        guard profiles.count > 1 else { throw ProfileStoreError.lastProfile }
        profiles.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = profiles[0].id
        }
    }
}
