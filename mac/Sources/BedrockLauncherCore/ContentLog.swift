import Foundation

/// One entry of the game's content log: pack loading, scripting and texture problems.
public struct ContentLogEntry: Equatable, Sendable {
    public let time: String
    public let level: String
    public let area: String
    public let message: String
}

/// Reads `games/com.mojang/logs/ContentLog*.txt`, which the game writes when
/// `content_log_file` is on. Entry lines look like `11:51:34[Texture][error]-message`.
public enum ContentLog {
    public static func latestFile(dataFolder: URL) -> URL? {
        let logs = dataFolder.appendingPathComponent("games/com.mojang/logs", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("ContentLog") && $0.pathExtension == "txt" }
            .max { modified($0) < modified($1) }
    }

    public static func parse(_ text: String) -> [ContentLogEntry] {
        var entries: [ContentLogEntry] = []
        // The game writes \r\n line endings, with a blank line between entries.
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let entry = entry(from: line) {
                entries.append(entry)
            } else if let last = entries.popLast() {
                entries.append(ContentLogEntry(time: last.time, level: last.level, area: last.area,
                                               message: last.message + "\n" + line))
            }
        }
        return entries
    }

    private static func entry(from line: String) -> ContentLogEntry? {
        let pattern = /^(\d{2}:\d{2}:\d{2})\[([^\]]*)\]\[([^\]]*)\]-(.*)$/
        guard let m = line.wholeMatch(of: pattern) else { return nil }
        return ContentLogEntry(time: String(m.1), level: String(m.3), area: String(m.2), message: String(m.4))
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
