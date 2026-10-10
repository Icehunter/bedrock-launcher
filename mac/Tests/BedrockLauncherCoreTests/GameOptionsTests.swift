import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct GameOptionsTests {
    func dataFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    func optionsFile(_ data: URL) -> URL {
        data.appendingPathComponent("games/com.mojang/minecraftpe/options.txt")
    }
    func write(_ text: String, _ data: URL) throws {
        let f = optionsFile(data)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: f, atomically: true, encoding: .utf8)
    }

    @Test func setsExistingKey() throws {
        let data = dataFolder()
        try write("gfx_vsync:1\ncontent_log_file:0\ngraphics_mode:1\n", data)
        try GameOptions.set("content_log_file", to: "1", dataFolder: data)
        #expect(try String(contentsOf: optionsFile(data), encoding: .utf8) == "gfx_vsync:1\ncontent_log_file:1\ngraphics_mode:1\n")
    }

    @Test func appendsMissingKey() throws {
        let data = dataFolder()
        try write("gfx_vsync:1\n", data)
        try GameOptions.set("content_log_file", to: "1", dataFolder: data)
        #expect(try String(contentsOf: optionsFile(data), encoding: .utf8) == "gfx_vsync:1\ncontent_log_file:1\n")
    }

    @Test func createsMissingFile() throws {
        let data = dataFolder()
        try GameOptions.set("content_log_file", to: "1", dataFolder: data)
        #expect(try String(contentsOf: optionsFile(data), encoding: .utf8) == "content_log_file:1\n")
    }
}
