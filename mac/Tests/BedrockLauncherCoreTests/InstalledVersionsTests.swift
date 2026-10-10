import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct InstalledVersionsTests {
    let fm = FileManager.default
    let versions: URL

    init() throws {
        versions = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
    }

    @discardableResult
    func game(_ name: String, real: Bool = true) throws -> URL {
        let folder = versions.appendingPathComponent(name, isDirectory: true)
        let lib = folder.appendingPathComponent("lib/arm64-v8a", isDirectory: true)
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        if real {
            try Data().write(to: lib.appendingPathComponent("libminecraftpe.so"))
        }
        return folder
    }

    @Test func listsOnlyRealGameFolders() throws {
        try game("1.26.52.3")
        try game("half-copied", real: false)
        try "x".write(to: versions.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        #expect(InstalledVersions.list(versionsFolder: versions).map(\.name) == ["1.26.52.3"])
    }

    @Test func sortsByVersionNumber() throws {
        try game("1.26.52.3")
        try game("1.26.9.1")
        try game("1.26.33.1")
        #expect(InstalledVersions.list(versionsFolder: versions).map(\.name) == ["1.26.9.1", "1.26.33.1", "1.26.52.3"])
    }

    @Test func newestIsHighest() throws {
        try game("1.26.9.1")
        try game("1.26.52.3")
        #expect(InstalledVersions.newest(versionsFolder: versions)?.name == "1.26.52.3")
    }

    @Test func noVersionsFolderGivesEmptyList() {
        let missing = versions.appendingPathComponent("nope", isDirectory: true)
        #expect(InstalledVersions.list(versionsFolder: missing).isEmpty)
        #expect(InstalledVersions.newest(versionsFolder: missing) == nil)
    }

    @Test func deleteRemovesFolder() throws {
        let folder = try game("1.26.52.3")
        let v = try #require(InstalledVersions.list(versionsFolder: versions).first)
        try InstalledVersions.delete(v)
        #expect(!fm.fileExists(atPath: folder.path))
    }
}
