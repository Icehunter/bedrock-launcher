import Foundation

/// Edits the game's own settings file, `games/com.mojang/minecraftpe/options.txt`,
/// which holds one `key:value` per line.
public enum GameOptions {
    public static func file(dataFolder: URL) -> URL {
        dataFolder.appendingPathComponent("games/com.mojang/minecraftpe/options.txt")
    }

    /// Sets `key` to `value`, keeping every other line as it is. Creates the
    /// file when the game has not written it yet.
    public static func set(_ key: String, to value: String, dataFolder: URL) throws {
        let url = file(dataFolder: dataFolder)
        var lines: [String] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            lines = text.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
        }
        let prefix = key + ":"
        if let i = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            lines[i] = prefix + value
        } else {
            lines.append(prefix + value)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
