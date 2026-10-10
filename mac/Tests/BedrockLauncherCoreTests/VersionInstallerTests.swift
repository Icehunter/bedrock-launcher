import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct VersionInstallerTests {
    let fm = FileManager.default
    let work: URL
    let versions: URL

    init() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        versions = work.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
    }

    func contents(_ url: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    @Test func installsSplitsThenBase() throws {
        let apks = try APKFixture.set(in: work)
        let v = try VersionInstaller.install(apks: apks, versionsFolder: versions)
        #expect(v.name == "1.2.3")
        #expect(contents(versions) == ["1.2.3"])
        let manifest = try Data(contentsOf: v.folder.appendingPathComponent("AndroidManifest.xml"))
        #expect(manifest == APKFixture.manifest("1.2.3"))
        #expect(fm.fileExists(atPath: v.folder.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so").path))
        #expect(!fm.fileExists(atPath: v.folder.appendingPathComponent("META-INF").path))
    }

    @Test func findsBaseByClassesDex() throws {
        let apks = try APKFixture.set(in: work)
        #expect(try VersionInstaller.baseAPK(of: apks).lastPathComponent == "odd-name.apk")
        #expect(try VersionInstaller.baseAPK(of: apks.reversed()).lastPathComponent == "odd-name.apk")
    }

    @Test func refusesWithoutBase() throws {
        let apks = try APKFixture.set(in: work)
        #expect(throws: VersionInstaller.Error.noBaseAPK) {
            try VersionInstaller.install(apks: [apks[0]], versionsFolder: versions)
        }
        #expect(contents(versions).isEmpty)
    }

    @Test func refusesWithoutArm64Library() throws {
        let apks = try APKFixture.set(in: work)
        #expect(throws: VersionInstaller.Error.noArm64Library) {
            try VersionInstaller.install(apks: [apks[1]], versionsFolder: versions)
        }
        #expect(contents(versions).isEmpty)
    }

    @Test func refusesExistingVersion() throws {
        let existing = versions.appendingPathComponent("1.2.3", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: existing.appendingPathComponent("marker"))
        let apks = try APKFixture.set(in: work)
        #expect(throws: VersionInstaller.Error.alreadyInstalled("1.2.3")) {
            try VersionInstaller.install(apks: apks, versionsFolder: versions)
        }
        #expect(contents(versions) == ["1.2.3"])
        #expect(contents(existing) == ["marker"])
    }

    @Test func cleansUpAfterBadZip() throws {
        var apks = try APKFixture.set(in: work)
        let bad = work.appendingPathComponent("broken.apk")
        try Data("not a zip".utf8).write(to: bad)
        apks.append(bad)
        #expect(throws: VersionInstaller.Error.self) {
            try VersionInstaller.install(apks: apks, versionsFolder: versions)
        }
        #expect(contents(versions).isEmpty)
    }

    @Test func errorsReadWell() {
        #expect(VersionInstaller.Error.alreadyInstalled("1.2.3").errorDescription == "Minecraft 1.2.3 is already installed")
        #expect(VersionInstaller.Error.noArm64Library.errorDescription == "These APK files have no arm64 game library")
    }

    @Test func listSkipsInstallingFolders() throws {
        let lib = versions.appendingPathComponent(".installing-x/lib/arm64-v8a", isDirectory: true)
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data().write(to: lib.appendingPathComponent("libminecraftpe.so"))
        #expect(InstalledVersions.list(versionsFolder: versions).isEmpty)
    }
}
