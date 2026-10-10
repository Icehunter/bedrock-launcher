import Foundation

/// One result line from `bedrock-gplay`.
public enum GooglePlayEvent: Equatable, Sendable {
    case email(String)
    case versionCode(Int)
    case progress(name: String, done: Int64, total: Int64)
    case file(URL)
}

public enum GooglePlayError: Error, Equatable, LocalizedError {
    /// No saved Google token, or Google refused it.
    case signInNeeded(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .signInNeeded(let message): "Sign in to Google again (\(message))"
        case .failed(let message): message
        }
    }
}

/// Runs the `bedrock-gplay` helper, which does every Google Play call. The
/// helper keeps the device identity and saved token in `state`.
public struct GooglePlay: Sendable {
    public let helper: URL
    public let state: URL

    public init(helper: URL, state: URL) {
        self.helper = helper
        self.state = state
    }

    public var isSignedIn: Bool {
        FileManager.default.fileExists(atPath: state.appendingPathComponent("playdl.conf").path)
    }

    public static func parse(_ line: String) -> GooglePlayEvent? {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "email": return .email(parts[1])
        case "version-code": return Int(parts[1]).map(GooglePlayEvent.versionCode)
        case "file": return .file(URL(fileURLWithPath: parts[1]))
        case "progress":
            let p = parts[1].split(separator: " ").map(String.init)
            guard p.count == 3, let done = Int64(p[1]), let total = Int64(p[2]) else { return nil }
            return .progress(name: p[0], done: done, total: total)
        default: return nil
        }
    }

    /// Trades the token from Google's sign-in page for a saved one. The token
    /// goes to the helper on stdin, never on its command line.
    public func signIn(oauthToken: String) async throws -> String {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var email: String?
        try await run(["login", "--state", state.path], stdin: oauthToken + "\n") {
            if case .email(let e) = $0 { email = e }
        }
        guard let email else { throw GooglePlayError.failed("Google sign-in returned no account") }
        return email
    }

    public func signOut() throws {
        if FileManager.default.fileExists(atPath: state.path) {
            try FileManager.default.removeItem(at: state)
        }
    }

    public func latestVersionCode() async throws -> Int {
        var code: Int?
        try await run(["latest", "--state", state.path], stdin: nil) {
            if case .versionCode(let c) = $0 { code = c }
        }
        guard let code else { throw GooglePlayError.failed("Google Play returned no version") }
        return code
    }

    /// Downloads every APK file for `versionCode` into `folder`. `progress`
    /// gets bytes done and bytes total over all files seen so far. On failure
    /// or cancel, `folder` is removed.
    public func download(versionCode: Int, to folder: URL,
                         progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> [URL] {
        var files: [URL] = []
        var parts: [String: (done: Int64, total: Int64)] = [:]
        do {
            try await run(["download", "--state", state.path, "--version-code", String(versionCode), "--out", folder.path],
                          stdin: nil) { event in
                switch event {
                case .progress(let name, let done, let total):
                    parts[name] = (done, total)
                    progress(parts.values.reduce(0) { $0 + $1.done }, parts.values.reduce(0) { $0 + $1.total })
                case .file(let url):
                    files.append(url)
                default:
                    break
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return files
    }

    private final class Child: @unchecked Sendable {
        let process = Process()
    }

    private func run(_ arguments: [String], stdin: String?, onEvent: (GooglePlayEvent) -> Void) async throws {
        let child = Child()
        let process = child.process
        process.executableURL = helper
        process.arguments = arguments
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        // waitUntilExit can miss the exit when called from a Swift task, so
        // the exit status comes through the termination handler.
        let (exits, exitSink) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { exitSink.yield($0.terminationStatus); exitSink.finish() }
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? input.fileHandleForWriting.close()
        let errText = Task {
            var lines: [String] = []
            for try await line in err.fileHandleForReading.bytes.lines { lines.append(line) }
            return lines
        }

        try await withTaskCancellationHandler {
            for try await line in out.fileHandleForReading.bytes.lines {
                if let event = Self.parse(line) { onEvent(event) }
            }
        } onCancel: {
            child.process.terminate()
        }
        var status: Int32 = -1
        for await s in exits { status = s }
        let stderr = (try? await errText.value) ?? []
        if Task.isCancelled { throw CancellationError() }
        guard status != 0 else { return }

        let last = stderr.last { $0.hasPrefix("error ") } ?? ""
        if status == 3 {
            throw GooglePlayError.signInNeeded(String(last.dropFirst("error auth ".count)))
        }
        let message = String(last.dropFirst("error ".count))
        throw GooglePlayError.failed(message.isEmpty ? "The Google Play helper stopped (code \(status))" : message)
    }
}
