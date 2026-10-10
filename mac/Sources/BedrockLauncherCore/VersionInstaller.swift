import Foundation

/// Installs a game version from the APK files Google Play delivers: one base
/// APK plus split APKs (arm64 libraries, language, screen size, game assets).
public enum VersionInstaller {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case noBaseAPK
        case noArm64Library
        case alreadyInstalled(String)
        case unzipFailed(String)
        case badName(String)

        public var errorDescription: String? {
            switch self {
            case .noBaseAPK: "These APK files hold no base APK"
            case .noArm64Library: "These APK files have no arm64 game library"
            case .alreadyInstalled(let name): "Minecraft \(name) is already installed"
            case .unzipFailed(let file): "Could not unpack \(file)"
            case .badName(let name): "\"\(name)\" is not a usable version name"
            }
        }
    }

    /// The base APK is the one holding `classes.dex`.
    public static func baseAPK(of apks: [URL]) throws -> URL {
        for apk in apks {
            let list = try run("/usr/bin/unzip", ["-Z1", apk.path])
            if list.status == 0, list.output.split(separator: "\n").contains("classes.dex") {
                return apk
            }
        }
        throw Error.noBaseAPK
    }

    /// Unpacks every split, then the base last, since each split carries its
    /// own AndroidManifest.xml and only the base one is right. The files go to
    /// a hidden folder first and move to `versions/<versionName>` when done.
    public static func install(apks: [URL], versionsFolder: URL) throws -> GameVersion {
        let base = try baseAPK(of: apks)
        let order = apks.filter { $0 != base } + [base]
        return try installStaged(into: versionsFolder) { stage in
            for apk in order {
                // 11 means the META-INF pattern matched nothing.
                let result = try run("/usr/bin/unzip", ["-qo", apk.path, "-x", "META-INF/*", "-d", stage.path])
                guard result.status == 0 || result.status == 11 else {
                    throw Error.unzipFailed(apk.lastPathComponent)
                }
            }
        }
    }

    /// Runs `fill` on a fresh hidden folder in `versionsFolder`, checks the
    /// result is a game version and moves it into place. Any failure removes
    /// the hidden folder.
    static func installStaged(into versionsFolder: URL, _ fill: (URL) throws -> Void) throws -> GameVersion {
        let fm = FileManager.default
        try fm.createDirectory(at: versionsFolder, withIntermediateDirectories: true)
        let stage = versionsFolder.appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        try fill(stage)
        guard fm.fileExists(atPath: stage.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so").path) else {
            throw Error.noArm64Library
        }
        let manifest = try AndroidManifest.read(file: stage.appendingPathComponent("AndroidManifest.xml"))
        guard isUsableName(manifest.versionName) else { throw Error.badName(manifest.versionName) }
        let target = versionsFolder.appendingPathComponent(manifest.versionName, isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else { throw Error.alreadyInstalled(manifest.versionName) }
        try fm.moveItem(at: stage, to: target)
        return GameVersion(name: manifest.versionName, folder: target)
    }

    /// Version names become folder names, so only plain names pass.
    public static func isUsableName(_ name: String) -> Bool {
        name != "." && name != ".." && !name.hasPrefix(".")
            && name.range(of: "^[0-9A-Za-z._-]+$", options: .regularExpression) != nil
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // waitUntilExit can miss the exit on some threads; the handler does not.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
