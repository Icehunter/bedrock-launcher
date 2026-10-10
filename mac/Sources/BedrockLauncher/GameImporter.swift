import Foundation

enum GameStore {
    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BedrockLauncher", isDirectory: true)
    static var gameDir: URL { root.appendingPathComponent("game", isDirectory: true) }
    static var mainLib: URL { gameDir.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so") }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: mainLib.path) }
}

enum ImportError: LocalizedError {
    case unzip(String)
    case noArm64Libs
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unzip(let s): return "unzip failed: \(s)"
        case .noArm64Libs:
            return "No lib/arm64-v8a/libminecraftpe.so in this file. Split APKs keep native libs in the config.arm64_v8a split; import that one too."
        case .unsupported(let e): return "Unsupported file type .\(e)"
        }
    }
}

enum GameImporter {
    static func run(_ file: URL) throws -> String {
        switch file.pathExtension.lowercased() {
        case "apk":
            try unzip(file, patterns: ["lib/arm64-v8a/*", "assets/*"], into: GameStore.gameDir, wipe: false)
            guard GameStore.isInstalled else { throw ImportError.noArm64Libs }
            return "Imported APK into \(GameStore.gameDir.path)"
        case "ipa":
            let dest = GameStore.root.appendingPathComponent("ios", isDirectory: true)
            try unzip(file, patterns: ["Payload/*"], into: dest, wipe: true)
            return "Extracted IPA into \(dest.path). The IPA loader is not built yet."
        case let e:
            throw ImportError.unsupported(e)
        }
    }

    private static func unzip(_ file: URL, patterns: [String], into dest: URL, wipe: Bool) throws {
        let fm = FileManager.default
        if wipe { try? fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-q", "-o", file.path] + patterns + ["-d", dest.path]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        // 0 = ok, 1 = warnings, 11 = no files matched (checked by the caller)
        guard p.terminationStatus <= 1 || p.terminationStatus == 11 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ImportError.unzip(msg)
        }
    }
}
