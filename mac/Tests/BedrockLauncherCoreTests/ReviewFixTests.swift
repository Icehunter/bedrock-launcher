import Foundation
import Testing
@testable import BedrockLauncherCore

/// Cancel, symlinks in archives, and a helper that quits before reading stdin.
@Suite struct ReviewFixTests {
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

    /// A zip holding `link -> target` plus `files`, symlink kept as a link.
    func zipWithLink(_ name: String, link: String, target: String, files: [String: Data]) throws -> URL {
        let stage = work.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        for (path, data) in files {
            let url = stage.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try fm.createSymbolicLink(atPath: stage.appendingPathComponent(link).path, withDestinationPath: target)
        let file = work.appendingPathComponent(name)
        #expect(try VersionInstaller.run("/bin/sh", ["-c", "cd '\(stage.path)' && /usr/bin/zip -qry '\(file.path)' ."]).status == 0)
        return file
    }

    @Test func installStopsWhenCancelled() throws {
        let apks = try APKFixture.set(in: work)
        #expect(throws: CancellationError.self) {
            try VersionInstaller.install(apks: apks, versionsFolder: versions, shouldStop: { true })
        }
        #expect(contents(versions).isEmpty)
    }

    @Test func importStopsWhenCancelled() throws {
        let apks = try APKFixture.set(in: work)
        let v = try VersionInstaller.install(apks: apks, versionsFolder: versions)
        let file = work.appendingPathComponent("x.mcversion")
        try ReleaseArchive.export(v, to: file)
        let other = work.appendingPathComponent("other", isDirectory: true)
        #expect(throws: CancellationError.self) {
            try ReleaseArchive.importFile(file, versionsFolder: other, shouldStop: { true })
        }
        #expect(contents(other).isEmpty)
    }

    @Test func exportStopsWhenCancelled() throws {
        let v = try VersionInstaller.install(apks: try APKFixture.set(in: work), versionsFolder: versions)
        let out = work.appendingPathComponent("out", isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        #expect(throws: CancellationError.self) {
            try ReleaseArchive.export(v, to: out.appendingPathComponent("x.mcversion"), shouldStop: { true })
        }
        #expect(contents(out).isEmpty)
    }

    @Test func installRefusesSymlinks() throws {
        let outside = work.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        var apks = try APKFixture.set(in: work)
        apks.append(try zipWithLink("evil.apk", link: "lib2", target: outside.path, files: ["readme": Data("x".utf8)]))
        #expect(throws: VersionInstaller.Error.unsafeArchive("evil.apk")) {
            try VersionInstaller.install(apks: apks, versionsFolder: versions)
        }
        #expect(contents(versions).isEmpty)
        #expect(contents(outside).isEmpty)
    }

    @Test func importRefusesSymlinks() throws {
        let file = try zipWithLink("evil.mcversion", link: "assets", target: "/tmp", files: [
            "version.json": Data("{\"name\":\"1.2.3\",\"versionCode\":123}".utf8),
            "AndroidManifest.xml": APKFixture.manifest("1.2.3"),
            "lib/arm64-v8a/libminecraftpe.so": Data("game".utf8),
        ])
        #expect(throws: VersionInstaller.Error.unsafeArchive("evil.mcversion")) {
            try ReleaseArchive.importFile(file, versionsFolder: versions)
        }
        #expect(contents(versions).isEmpty)
    }

    @Test func helperQuittingEarlyDoesNotKillTheApp() async throws {
        let script = work.appendingPathComponent("bedrock-gplay")
        try "#!/bin/sh\necho 'error auth cannot open state' >&2\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let play = GooglePlay(helper: script, state: work.appendingPathComponent("google"))
        // Bigger than a pipe's buffer, so the write meets a closed pipe.
        let token = String(repeating: "t", count: 1 << 20)
        await #expect(throws: GooglePlayError.signInNeeded("cannot open state")) {
            try await play.signIn(oauthToken: token)
        }
    }
}

@Suite struct OwnerTestFixTests {
    @Test func downloadCreatesMissingParentFolders() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let out = work.appendingPathComponent("apks/972605203", isDirectory: true)
        let script = work.appendingPathComponent("bedrock-gplay")
        // Like the real helper, it needs the parent of --out to exist.
        try """
        #!/bin/sh
        [ -d "\(out.deletingLastPathComponent().path)" ] || { echo 'error cannot open' >&2; exit 1; }
        echo "file \(out.path)/base.apk"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let play = GooglePlay(helper: script, state: work.appendingPathComponent("google"))
        let files = try await play.download(versionCode: 972605203, to: out) { _, _ in }
        #expect(files.map(\.lastPathComponent) == ["base.apk"])
    }

    @Test(arguments: [
        ("Minecraft-1.26.52.3.mcversion.mcversion", "Minecraft-1.26.52.3.mcversion"),
        ("Minecraft-1.26.52.3.mcversion", "Minecraft-1.26.52.3.mcversion"),
        ("Minecraft-1.26.52.3", "Minecraft-1.26.52.3.mcversion"),
        ("kids", "kids.mcversion"),
    ])
    func exportFileGetsOneExtension(_ picked: String, _ expected: String) {
        let url = ReleaseArchive.exportFile(URL(fileURLWithPath: "/tmp/\(picked)"))
        #expect(url.lastPathComponent == expected)
    }
}
