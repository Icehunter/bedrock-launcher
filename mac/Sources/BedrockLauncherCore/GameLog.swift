import Foundation

/// The game's output: the newest lines in memory for the Log page, and every
/// line in a file. Safe to append to from any thread.
public final class GameLog: @unchecked Sendable {
    public let file: URL
    public let capacity: Int
    public var onChange: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var buffer: [String] = []
    private var handle: FileHandle?

    public init(file: URL, capacity: Int = 20_000) {
        self.file = file
        self.capacity = capacity
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
    }

    deinit {
        try? handle?.close()
    }

    public var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func append(_ line: String) {
        lock.lock()
        buffer.append(line)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        handle?.write(Data((line + "\n").utf8))
        lock.unlock()
        onChange?()
    }
}
