import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct PackLinkerTests {
    let fm = FileManager.default
    let base: URL
    let data: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        data = base.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    }

    func pack(_ name: String, modules: [String]?) throws -> URL {
        let folder = base.appendingPathComponent("src", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest: [String: Any] = ["format_version": 2, "header": ["name": name]]
        if let modules {
            manifest["modules"] = modules.map { ["type": $0] }
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }

    func dev(_ kind: String) -> URL {
        data.appendingPathComponent("games/com.mojang/development_\(kind)_packs", isDirectory: true)
    }

    @Test func resourceModuleLinksIntoResourceFolder() throws {
        let p = try pack("Ashen RP", modules: ["resources"])
        let linked = try PackLinker.link(p, dataFolder: data)
        #expect(linked.kind == .resource)
        let link = dev("resource").appendingPathComponent("Ashen RP")
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == p.path)
    }

    @Test func dataModuleLinksIntoBehaviorFolder() throws {
        let p = try pack("Ashen BP", modules: ["data", "script"])
        #expect(try PackLinker.link(p, dataFolder: data).kind == .behavior)
        #expect(fm.fileExists(atPath: dev("behavior").appendingPathComponent("Ashen BP").path))
    }

    @Test func refusesMissingManifest() throws {
        let folder = base.appendingPathComponent("empty", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: PackLinkerError.noManifest) { try PackLinker.link(folder, dataFolder: data) }
    }

    @Test func refusesNoModules() throws {
        let p = try pack("NoModules", modules: nil)
        #expect(throws: PackLinkerError.unknownPackType) { try PackLinker.link(p, dataFolder: data) }
    }

    @Test func refusesMixedResourceAndData() throws {
        let p = try pack("Mixed", modules: ["resources", "data"])
        #expect(throws: PackLinkerError.mixedPackType) { try PackLinker.link(p, dataFolder: data) }
    }

    @Test func refusesExistingRealFolder() throws {
        let p = try pack("Taken", modules: ["resources"])
        let existing = dev("resource").appendingPathComponent("Taken")
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try "keep".write(to: existing.appendingPathComponent("mine.txt"), atomically: true, encoding: .utf8)
        #expect(throws: PackLinkerError.nameTaken) { try PackLinker.link(p, dataFolder: data) }
        #expect(try String(contentsOf: existing.appendingPathComponent("mine.txt"), encoding: .utf8) == "keep")
    }

    @Test func listsAndUnlinks() throws {
        let p = try pack("Listed", modules: ["resources"])
        let linked = try PackLinker.link(p, dataFolder: data)
        try fm.createDirectory(at: dev("resource").appendingPathComponent("NotALink"), withIntermediateDirectories: true)
        #expect(PackLinker.linkedPacks(dataFolder: data) == [linked])
        try PackLinker.unlink(linked, dataFolder: data)
        #expect(PackLinker.linkedPacks(dataFolder: data).isEmpty)
        #expect(fm.fileExists(atPath: p.appendingPathComponent("manifest.json").path))
    }

    @Test func errorsHaveReadableMessages() {
        #expect(PackLinkerError.mixedPackType.message.contains("both"))
        #expect(PackLinkerError.nameTaken.message.contains("already"))
    }
}
