import Foundation

public enum PackKind: Equatable, Sendable {
    case resource, behavior

    var folderName: String {
        switch self {
        case .resource: "development_resource_packs"
        case .behavior: "development_behavior_packs"
        }
    }
}

/// A pack folder linked into one of the game's development pack folders.
public struct LinkedPack: Equatable, Sendable {
    public let name: String
    public let kind: PackKind
    public let target: URL
}

public enum PackLinkerError: Error, Equatable {
    case noManifest
    case unknownPackType
    case mixedPackType
    case nameTaken

    public var message: String {
        switch self {
        case .noManifest: "This folder has no manifest.json, so it is not a pack."
        case .unknownPackType: "The manifest.json lists no resources or data module, so the pack type is unknown."
        case .mixedPackType: "The manifest.json has both resources and data modules. Link the resource pack and behavior pack folders one at a time."
        case .nameTaken: "A pack with this folder name is already in the development pack folder."
        }
    }
}

/// Links pack folders that live anywhere (for example a git checkout) into the
/// game's development pack folders, where the game loads them without importing.
public enum PackLinker {
    public static func kind(ofPack folder: URL) throws -> PackKind {
        let manifest = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifest) else { throw PackLinkerError.noManifest }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let types = Set(((json?["modules"] as? [[String: Any]]) ?? []).compactMap { $0["type"] as? String })
        let resource = types.contains("resources")
        let behavior = types.contains("data") || types.contains("script")
        switch (resource, behavior) {
        case (true, false): return .resource
        case (false, true): return .behavior
        case (true, true): throw PackLinkerError.mixedPackType
        case (false, false): throw PackLinkerError.unknownPackType
        }
    }

    public static func link(_ folder: URL, dataFolder: URL) throws -> LinkedPack {
        let kind = try kind(ofPack: folder)
        let devFolder = devFolder(kind, dataFolder: dataFolder)
        let name = folder.standardizedFileURL.lastPathComponent
        let link = devFolder.appendingPathComponent(name)
        let fm = FileManager.default
        // Never replace anything already there, including a real folder of the user's.
        if (try? fm.attributesOfItem(atPath: link.path)) != nil {
            throw PackLinkerError.nameTaken
        }
        try fm.createDirectory(at: devFolder, withIntermediateDirectories: true)
        let target = URL(fileURLWithPath: folder.standardizedFileURL.path, isDirectory: true)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        return LinkedPack(name: name, kind: kind, target: target)
    }

    /// Symlinked packs in both development folders. Real folders are left out.
    public static func linkedPacks(dataFolder: URL) -> [LinkedPack] {
        let fm = FileManager.default
        var packs: [LinkedPack] = []
        for kind in [PackKind.resource, .behavior] {
            let folder = devFolder(kind, dataFolder: dataFolder)
            for name in ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() {
                let path = folder.appendingPathComponent(name).path
                if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
                    packs.append(LinkedPack(name: name, kind: kind, target: URL(fileURLWithPath: dest, isDirectory: true)))
                }
            }
        }
        return packs
    }

    /// Removes only the link; the pack folder it points to is not touched.
    public static func unlink(_ pack: LinkedPack, dataFolder: URL) throws {
        let link = devFolder(pack.kind, dataFolder: dataFolder).appendingPathComponent(pack.name)
        _ = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        try FileManager.default.removeItem(atPath: link.path)
    }

    static func devFolder(_ kind: PackKind, dataFolder: URL) -> URL {
        dataFolder.appendingPathComponent("games/com.mojang", isDirectory: true)
            .appendingPathComponent(kind.folderName, isDirectory: true)
    }
}
