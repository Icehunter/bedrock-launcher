import Foundation

/// Moves a game version between Macs as one `.mcversion` file: a zip of the
/// version folder plus `version.json`. The export holds the game as Google
/// Play ships it, without the updates mod's changes or files the game writes.
public enum ReleaseArchive {
    public static let fileExtension = "mcversion"

    public struct Info: Codable, Equatable, Sendable {
        public let name: String
        public let versionCode: Int
    }

    public enum Error: Swift.Error, Equatable, LocalizedError {
        case notAnExport
        case zipFailed

        public var errorDescription: String? {
            switch self {
            case .notAnExport: "This file is not a game version exported by Bedrock Launcher"
            case .zipFailed: "Could not write the export file"
            }
        }
    }

    public static func fileName(for v: GameVersion) -> String {
        "Minecraft-\(v.name).\(fileExtension)"
    }

    /// The file the save panel picked, with exactly one `.mcversion` ending.
    public static func exportFile(_ picked: URL) -> URL {
        var url = picked
        while url.pathExtension == fileExtension { url.deletePathExtension() }
        return url.appendingPathExtension(fileExtension)
    }

    public static func export(_ v: GameVersion, to file: URL, shouldStop: () -> Bool = { false }) throws {
        let fm = FileManager.default
        let manifest = try AndroidManifest.read(file: v.folder.appendingPathComponent("AndroidManifest.xml"))
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: v.folder, create: true)
        defer { try? fm.removeItem(at: scratch) }
        // A copy on the same disk shares the file data, so this takes no space.
        let stage = scratch.appendingPathComponent("version", isDirectory: true)
        try fm.copyItem(at: v.folder, to: stage)
        try? fm.removeItem(at: stage.appendingPathComponent("assets/data"))
        let files = try fm.subpathsOfDirectory(atPath: stage.path)
        for path in files where (path as NSString).lastPathComponent == ".DS_Store"
            || path.range(of: "\\.bck[0-9]+$", options: .regularExpression) != nil {
            try fm.removeItem(at: stage.appendingPathComponent(path))
        }
        for path in files where path.hasSuffix(".bck") {
            let original = stage.appendingPathComponent(path)
            let target = original.deletingPathExtension()
            try? fm.removeItem(at: target)
            try fm.moveItem(at: original, to: target)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(Info(name: manifest.versionName, versionCode: manifest.versionCode))
            .write(to: stage.appendingPathComponent("version.json"))

        if shouldStop() { throw CancellationError() }
        let partial = file.appendingPathExtension("partial")
        try? fm.removeItem(at: partial)
        guard try VersionInstaller.run("/usr/bin/ditto", ["-c", "-k", stage.path, partial.path]).status == 0 else {
            try? fm.removeItem(at: partial)
            throw Error.zipFailed
        }
        if shouldStop() {
            try? fm.removeItem(at: partial)
            throw CancellationError()
        }
        try? fm.removeItem(at: file)
        try fm.moveItem(at: partial, to: file)
    }

    public static func importFile(_ file: URL, versionsFolder: URL,
                                  shouldStop: () -> Bool = { false }) throws -> GameVersion {
        if try VersionInstaller.hasLinks(file) { throw VersionInstaller.Error.unsafeArchive(file.lastPathComponent) }
        return try VersionInstaller.installStaged(into: versionsFolder, shouldStop: shouldStop) { stage in
            guard try VersionInstaller.run("/usr/bin/ditto", ["-x", "-k", file.path, stage.path]).status == 0 else {
                throw Error.notAnExport
            }
            let infoFile = stage.appendingPathComponent("version.json")
            guard let data = try? Data(contentsOf: infoFile),
                  let info = try? JSONDecoder().decode(Info.self, from: data)
            else { throw Error.notAnExport }
            guard VersionInstaller.isUsableName(info.name) else { throw VersionInstaller.Error.badName(info.name) }
            try FileManager.default.removeItem(at: infoFile)
        }
    }
}
