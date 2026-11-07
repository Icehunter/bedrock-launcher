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

    /// Hand-parsed: a regex per line is too slow on logs of tens of thousands of lines.
    private static func entry(from line: String) -> ContentLogEntry? {
        let u = Array(line.utf8.prefix(8))
        guard u.count == 8, u[2] == 0x3A, u[5] == 0x3A,
              [0, 1, 3, 4, 6, 7].allSatisfy({ (0x30...0x39).contains(u[$0]) }) else { return nil }
        var rest = line.dropFirst(8)
        guard rest.first == "[", let areaEnd = rest.firstIndex(of: "]") else { return nil }
        let area = rest[rest.index(after: rest.startIndex)..<areaEnd]
        rest = rest[rest.index(after: areaEnd)...]
        guard rest.first == "[", let levelEnd = rest.firstIndex(of: "]") else { return nil }
        let level = rest[rest.index(after: rest.startIndex)..<levelEnd]
        rest = rest[rest.index(after: levelEnd)...]
        guard rest.first == "-" else { return nil }
        return ContentLogEntry(time: String(line.prefix(8)), level: String(level), area: String(area),
                               message: String(rest.dropFirst()))
    }

    /// Identical level, area and message collapsed into one row with a count,
    /// in order of first appearance.
    public static func grouped(_ entries: [ContentLogEntry]) -> [(entry: ContentLogEntry, count: Int)] {
        var index: [String: Int] = [:]
        var out: [(entry: ContentLogEntry, count: Int)] = []
        for e in entries {
            let key = e.level + "\u{0}" + e.area + "\u{0}" + e.message
            if let i = index[key] {
                out[i].count += 1
            } else {
                index[key] = out.count
                out.append((e, 1))
            }
        }
        return out
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
