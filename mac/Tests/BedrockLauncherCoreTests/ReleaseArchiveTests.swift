import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct ReleaseArchiveTests {
    let fm = FileManager.default
    let work: URL
    let versions: URL
    let other: URL

    init() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        versions = work.appendingPathComponent("versions", isDirectory: true)
        other = work.appendingPathComponent("other-mac", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    }

    /// An installed version the updates mod has patched and the game has run.
    func installed(_ name: String = "1.2.3") throws -> GameVersion {
        let folder = versions.appendingPathComponent(name, isDirectory: true)
        let files: [String: String] = [
            "lib/arm64-v8a/libminecraftpe.so": "game",
            "lib/arm64-v8a/libmaesdk.so": "patched",
            "lib/arm64-v8a/libmaesdk.so.bck": "original",
            "lib/arm64-v8a/libmaesdk.so.bck1": "older",
            "assets/data/minecraftpe/options.txt": "runtime",
            "assets/vanilla.txt": "asset",
            ".DS_Store": "finder",
            "assets/.DS_Store": "finder",
        ]
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try APKFixture.manifest(name).write(to: folder.appendingPathComponent("AndroidManifest.xml"))
        return GameVersion(name: name, folder: folder)
    }

    func entries(_ zip: URL) throws -> [String] {
        try VersionInstaller.run("/usr/bin/unzip", ["-Z1", zip.path]).output
            .split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") }.sorted()
    }

    func entry(_ zip: URL, _ path: String) throws -> String {
        try VersionInstaller.run("/usr/bin/unzip", ["-p", zip.path, path]).output
    }

    func export(_ v: GameVersion) throws -> URL {
        let file = work.appendingPathComponent(ReleaseArchive.fileName(for: v))
        try ReleaseArchive.export(v, to: file)
        return file
    }

    /// A zip with the given files, standing in for a hand-made or damaged export.
    func zip(_ files: [String: Data]) throws -> URL {
        try APKFixture.write(to: work.appendingPathComponent("\(UUID().uuidString).mcversion"), entries: files)
    }

    @Test func fileNameUsesVersion() throws {
        #expect(ReleaseArchive.fileName(for: try installed("1.26.52.3")) == "Minecraft-1.26.52.3.mcversion")
    }

    @Test func exportRestoresBackups() throws {
        let v = try installed()
        let file = try export(v)
        #expect(try entry(file, "lib/arm64-v8a/libmaesdk.so") == "original")
        #expect(try entries(file).filter { $0.contains(".bck") }.isEmpty)
        #expect(try String(contentsOf: v.folder.appendingPathComponent("lib/arm64-v8a/libmaesdk.so"), encoding: .utf8) == "patched")
        #expect(fm.fileExists(atPath: v.folder.appendingPathComponent("lib/arm64-v8a/libmaesdk.so.bck").path))
    }

    @Test func exportSkipsRuntimeFiles() throws {
        let list = try entries(try export(try installed()))
        #expect(list == [
            "AndroidManifest.xml", "assets/vanilla.txt", "lib/arm64-v8a/libmaesdk.so",
            "lib/arm64-v8a/libminecraftpe.so", "version.json",
        ])
    }

    @Test func exportWritesVersionJSON() throws {
        let json = try entry(try export(try installed()), "version.json")
        let info = try JSONDecoder().decode(ReleaseArchive.Info.self, from: Data(json.utf8))
        #expect(info == ReleaseArchive.Info(name: "1.2.3", versionCode: 123))
    }

    @Test func roundTrip() throws {
        let file = try export(try installed())
        let v = try ReleaseArchive.importFile(file, versionsFolder: other)
        #expect(v.name == "1.2.3")
        let files = try fm.subpathsOfDirectory(atPath: v.folder.path)
            .filter { !(try! v.folder.appendingPathComponent($0).resourceValues(forKeys: [.isDirectoryKey]).isDirectory!) }
            .sorted()
        #expect(files == ["AndroidManifest.xml", "assets/vanilla.txt", "lib/arm64-v8a/libmaesdk.so", "lib/arm64-v8a/libminecraftpe.so"])
        #expect(try String(contentsOf: v.folder.appendingPathComponent("lib/arm64-v8a/libmaesdk.so"), encoding: .utf8) == "original")
    }

    @Test(arguments: ["../evil", "", "a/b", ".."])
    func importRefusesBadName(_ name: String) throws {
        let file = try zip([
            "version.json": Data("{\"name\":\"\(name)\",\"versionCode\":123}".utf8),
            "AndroidManifest.xml": APKFixture.manifest("1.2.3"),
            "lib/arm64-v8a/libminecraftpe.so": Data("game".utf8),
        ])
        #expect(throws: VersionInstaller.Error.badName(name)) {
            try ReleaseArchive.importFile(file, versionsFolder: other)
        }
        #expect(try fm.contentsOfDirectory(atPath: other.path).isEmpty)
        #expect(try fm.contentsOfDirectory(atPath: work.path).sorted() == [file.lastPathComponent, "other-mac", "versions"].sorted())
    }

    @Test func importRefusesBadManifestName() throws {
        let file = try zip([
            "version.json": Data("{\"name\":\"../evil\",\"versionCode\":123}".utf8),
            "AndroidManifest.xml": APKFixture.manifest("../evil"),
            "lib/arm64-v8a/libminecraftpe.so": Data("game".utf8),
        ])
        #expect(throws: VersionInstaller.Error.badName("../evil")) {
            try ReleaseArchive.importFile(file, versionsFolder: other)
        }
        #expect(try fm.contentsOfDirectory(atPath: other.path).isEmpty)
    }

    @Test func importRefusesExisting() throws {
        let file = try export(try installed())
        #expect(throws: VersionInstaller.Error.alreadyInstalled("1.2.3")) {
            try ReleaseArchive.importFile(file, versionsFolder: versions)
        }
    }

    @Test func importRefusesPlainZip() throws {
        let file = try zip(["readme.txt": Data("hi".utf8)])
        #expect(throws: ReleaseArchive.Error.notAnExport) {
            try ReleaseArchive.importFile(file, versionsFolder: other)
        }
        #expect(try fm.contentsOfDirectory(atPath: other.path).isEmpty)
    }
}
