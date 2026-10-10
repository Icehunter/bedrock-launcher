import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct ContentLogTests {
    // Real lines from a 1.26.52.3 content log; entries are separated by blank lines.
    let sample = """
    11:51:33[Scripting][verbose]-Plugin Discovered [RealismCraft 2.6 Behavior Pack] PackId [ffc5f3ad]

    11:51:34[Texture][error]-textures/blocks/foo.png missing
    second line of the same entry

    """

    @Test func parsesContentLogLines() {
        let entries = ContentLog.parse(sample)
        #expect(entries.count == 2)
        #expect(entries[0] == ContentLogEntry(time: "11:51:33", level: "verbose", area: "Scripting",
                                              message: "Plugin Discovered [RealismCraft 2.6 Behavior Pack] PackId [ffc5f3ad]"))
        #expect(entries[1].time == "11:51:34")
        #expect(entries[1].area == "Texture")
        #expect(entries[1].level == "error")
        #expect(entries[1].message == "textures/blocks/foo.png missing\nsecond line of the same entry")
    }

    @Test func picksNewestLogFile() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logs = data.appendingPathComponent("games/com.mojang/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let old = logs.appendingPathComponent("ContentLog2026-10-10_11-50-23_1.txt")
        let new = logs.appendingPathComponent("ContentLog2026-10-10_11-51-23_1.txt")
        try "a".write(to: old, atomically: true, encoding: .utf8)
        try "b".write(to: new, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: old.path)
        try "x".write(to: logs.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        #expect(ContentLog.latestFile(dataFolder: data)?.lastPathComponent == new.lastPathComponent)
    }

    @Test func noLogFolderGivesNil() {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(ContentLog.latestFile(dataFolder: data) == nil)
    }
}
