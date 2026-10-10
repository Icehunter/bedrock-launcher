import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct GameRunnerTests {
    func logFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("game.log")
    }

    func shell(_ script: String) -> LaunchPlan {
        LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: [:])
    }

    /// Runs `script` and waits for the exit callback.
    func run(_ script: String, log: GameLog) async throws -> Int32 {
        let runner = GameRunner(log: log)
        return try await withCheckedThrowingContinuation { cont in
            runner.onExit = { code in cont.resume(returning: code) }
            do { try runner.start(shell(script)) } catch { cont.resume(throwing: error) }
        }
    }

    @Test func capturesStdoutAndStderr() async throws {
        let file = logFile()
        let log = GameLog(file: file)
        _ = try await run("echo out; echo err >&2", log: log)
        #expect(log.lines.contains("out"))
        #expect(log.lines.contains("err"))
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("out\n"))
        #expect(written.contains("err\n"))
    }

    @Test func reportsExitCode() async throws {
        let log = GameLog(file: logFile())
        let code = try await run("exit 3", log: log)
        #expect(code == 3)
        #expect(log.lines.last == "Game exited with code 3")
    }

    @Test func keepsOutputAfterCrash() async throws {
        let log = GameLog(file: logFile())
        let code = try await run("echo before; kill -9 $$", log: log)
        #expect(code != 0)
        #expect(log.lines.contains("before"))
        #expect(log.lines.last?.hasPrefix("Game exited with code") == true)
    }

    @Test func trimsToCapacity() throws {
        let file = logFile()
        let log = GameLog(file: file, capacity: 5)
        for i in 1...8 { log.append("line \(i)") }
        #expect(log.lines == ["line 4", "line 5", "line 6", "line 7", "line 8"])
        #expect(try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty }.count == 8)
    }
}
