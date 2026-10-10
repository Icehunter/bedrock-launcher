import Foundation

/// Writes zip files that look like APKs to the tests.
enum APKFixture {
    @discardableResult
    static func write(to file: URL, entries: [String: Data]) throws -> URL {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        for (path, data) in entries {
            let url = stage.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", file.path, "."]
        zip.currentDirectoryURL = stage
        try zip.run()
        zip.waitUntilExit()
        precondition(zip.terminationStatus == 0, "zip failed")
        return file
    }

    static func manifest(_ name: String, code: Int = 123) -> Data {
        AXMLFixture.make(package: "com.mojang.minecraftpe", versionName: name, versionCode: code, utf8: false)
    }

    /// A base APK and an arm64 split for version `name`.
    static func set(in folder: URL, name: String = "1.2.3") throws -> [URL] {
        let base = try write(to: folder.appendingPathComponent("odd-name.apk"), entries: [
            "AndroidManifest.xml": manifest(name),
            "classes.dex": Data("dex".utf8),
            "META-INF/CERT.SF": Data("sig".utf8),
        ])
        let split = try write(to: folder.appendingPathComponent("split_config.arm64_v8a.apk"), entries: [
            "AndroidManifest.xml": Data("split manifest".utf8),
            "lib/arm64-v8a/libminecraftpe.so": Data("game".utf8),
        ])
        return [split, base]
    }
}
