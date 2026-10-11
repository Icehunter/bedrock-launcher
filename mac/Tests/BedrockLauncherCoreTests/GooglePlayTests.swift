import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct GooglePlayTests {
    let fm = FileManager.default
    let work: URL
    let state: URL

    init() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        state = work.appendingPathComponent("google", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    /// A stand-in for bedrock-gplay that records its arguments and stdin.
    func helper(_ body: String, account: GoogleAccount? = GoogleAccount(email: "kid@example.com", token: "aas_et/saved")) throws -> GooglePlay {
        let script = work.appendingPathComponent("bedrock-gplay")
        try """
        #!/bin/bash
        printf '%s\\n' "$@" > "\(work.path)/args"
        cat > "\(work.path)/stdin" < /dev/stdin &
        wait
        \(body)
        """.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let credentials = MemoryCredentials()
        if let account { try credentials.save(account) }
        return GooglePlay(helper: script, state: state, credentials: credentials)
    }

    func recorded(_ name: String) throws -> String {
        try String(contentsOf: work.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func parsesEachLine() {
        #expect(GooglePlay.parse("email kid@example.com") == .email("kid@example.com"))
        #expect(GooglePlay.parse("version-code 972605203") == .versionCode(972605203))
        #expect(GooglePlay.parse("progress base.apk 10 200") == .progress(name: "base.apk", done: 10, total: 200))
        #expect(GooglePlay.parse("file /tmp/a b/base.apk") == .file(URL(fileURLWithPath: "/tmp/a b/base.apk")))
        #expect(GooglePlay.parse("version-code x") == nil)
        #expect(GooglePlay.parse("hello") == nil)
    }

    @Test func signInSendsTokenOnStdinOnly() async throws {
        let play = try helper("echo 'email kid@example.com'; echo 'token aas_et/new'", account: nil)
        #expect(!play.isSignedIn)
        let email = try await play.signIn(oauthToken: "oauth2_4/secret")
        #expect(email == "kid@example.com")
        #expect(try recorded("stdin") == "oauth2_4/secret\n")
        #expect(try !recorded("args").contains("secret"))
        #expect(try recorded("args") == "login\n--state\n\(state.path)\n")
        #expect(play.isSignedIn)
    }

    @Test func stateFolderIsPrivate() async throws {
        let play = try helper("echo 'email a@b.c'; echo 'token x'", account: nil)
        _ = try await play.signIn(oauthToken: "t")
        let mode = try fm.attributesOfItem(atPath: state.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func refusedTokenNeedsSignIn() async throws {
        let play = try helper("echo 'error auth token revoked' >&2; exit 3")
        await #expect(throws: GooglePlayError.signInNeeded("token revoked")) {
            try await play.latestVersionCode()
        }
    }

    @Test func otherFailuresCarryTheMessage() async throws {
        let play = try helper("echo 'error disk full' >&2; exit 1")
        await #expect(throws: GooglePlayError.failed("disk full")) {
            try await play.latestVersionCode()
        }
    }

    @Test func latestReadsVersionCode() async throws {
        let play = try helper("echo 'version-code 972605300'")
        #expect(try await play.latestVersionCode() == 972605300)
    }

    @Test func downloadReturnsFilesAndProgress() async throws {
        let out = work.appendingPathComponent("apks")
        let play = try helper("""
        echo 'progress base.apk 50 100'
        echo 'progress split_x.apk 25 100'
        echo "file \(out.path)/base.apk"
        echo "file \(out.path)/split_x.apk"
        """)
        let seen = Seen()
        let files = try await play.download(versionCode: 972605203, to: out) { done, total in seen.add(done, total) }
        #expect(files.map(\.lastPathComponent) == ["base.apk", "split_x.apk"])
        #expect(seen.last == [75, 200])
        #expect(try recorded("args") == "download\n--state\n\(state.path)\n--version-code\n972605203\n--out\n\(out.path)\n")
    }

    @Test func cancelledDownloadLeavesNothing() async throws {
        let out = work.appendingPathComponent("apks")
        let play = try helper("mkdir -p \"\(out.path)\"; touch \"\(out.path)/base.apk.partial\"; echo 'progress base.apk 1 100'; sleep 30")
        let task = Task { try await play.download(versionCode: 1, to: out) { _, _ in } }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!fm.fileExists(atPath: out.path))
    }

    @Test func failedDownloadLeavesNothing() async throws {
        let out = work.appendingPathComponent("apks")
        let play = try helper("mkdir -p \"\(out.path)\"; touch \"\(out.path)/base.apk.partial\"; echo 'error HTTP 403' >&2; exit 1")
        await #expect(throws: GooglePlayError.failed("HTTP 403")) {
            try await play.download(versionCode: 1, to: out) { _, _ in }
        }
        #expect(!fm.fileExists(atPath: out.path))
    }

    @Test func signOutRemovesState() async throws {
        let play = try helper("echo 'email a@b.c'; echo 'token x'", account: nil)
        _ = try await play.signIn(oauthToken: "t")
        try play.signOut()
        #expect(!fm.fileExists(atPath: state.path))
        #expect(!play.isSignedIn)
    }
}

final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Int64]] = []
    func add(_ done: Int64, _ total: Int64) { lock.withLock { values.append([done, total]) } }
    var last: [Int64]? { lock.withLock { values.last } }
}
