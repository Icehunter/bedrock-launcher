import Foundation

/// Starts the game and feeds its stdout and stderr, line by line, into a GameLog.
public final class GameRunner: @unchecked Sendable {
    public let log: GameLog
    /// Called once, after all output has been logged, with the exit code
    /// (or the signal number when the game was killed).
    public var onExit: (@Sendable (Int32) -> Void)?

    private let queue = DispatchQueue(label: "GameRunner")
    private var process: Process?

    public init(log: GameLog) {
        self.log = log
    }

    public var isRunning: Bool {
        queue.sync { process?.isRunning ?? false }
    }

    public func start(_ plan: LaunchPlan) throws {
        let process = Process()
        process.executableURL = plan.executable
        process.arguments = plan.arguments
        process.environment = plan.environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Exit is reported only after both streams reach their end, so no
        // output can land after the exit line.
        let done = DispatchGroup()
        done.enter()
        done.enter()
        done.enter()
        process.terminationHandler = { _ in done.leave() }
        try process.run()
        queue.sync { self.process = process }

        read(out.fileHandleForReading, done: done)
        read(err.fileHandleForReading, done: done)

        done.notify(queue: queue) { [weak self] in
            guard let self else { return }
            let code = process.terminationStatus
            self.log.append("Game exited with code \(code)")
            self.process = nil
            self.onExit?(code)
        }
    }

    private func read(_ handle: FileHandle, done: DispatchGroup) {
        let log = self.log
        let queue = self.queue
        DispatchQueue.global(qos: .utility).async {
            var pending = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...nl)
                    queue.sync { log.append(line) }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                queue.sync { log.append(line) }
            }
            done.leave()
        }
    }
}
