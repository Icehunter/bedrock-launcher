import Foundation

/// A named way to start the game: which version, which data folder, what window size.
public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// nil means the newest installed version.
    public var gameVersion: String?
    /// nil means the launcher's default folder for this profile.
    public var dataFolder: URL?
    public var windowWidth: Int?
    public var windowHeight: Int?

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
