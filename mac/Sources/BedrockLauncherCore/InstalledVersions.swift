import Foundation

/// An unpacked game version in the launcher's versions folder.
public struct GameVersion: Equatable, Comparable, Sendable {
    public let name: String
    public let folder: URL

    var numbers: [Int] {
        name.split(separator: ".").map { Int($0) ?? 0 }
    }

    public static func < (a: GameVersion, b: GameVersion) -> Bool {
        a.numbers.lexicographicallyPrecedes(b.numbers)
    }
}

public enum InstalledVersions {
    /// Folders that hold `lib/arm64-v8a/libminecraftpe.so`, oldest first.
    /// Hidden folders, such as installs still in progress, are left out.
    public static func list(versionsFolder: URL) -> [GameVersion] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: versionsFolder.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .map { GameVersion(name: $0, folder: versionsFolder.appendingPathComponent($0, isDirectory: true)) }
            .filter { fm.fileExists(atPath: $0.folder.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so").path) }
            .sorted()
    }

    public static func newest(versionsFolder: URL) -> GameVersion? {
        list(versionsFolder: versionsFolder).last
    }

    public static func delete(_ version: GameVersion) throws {
        try FileManager.default.removeItem(at: version.folder)
    }
}
