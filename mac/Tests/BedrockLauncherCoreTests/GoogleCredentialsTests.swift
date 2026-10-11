import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct GoogleCredentialsTests {
    let fm = FileManager.default
    let work: URL
    let state: URL
    let credentials = MemoryCredentials()
    let account = GoogleAccount(email: "kid@example.com", token: "aas_et/secret")

    init() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        state = work.appendingPathComponent("google", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    /// A stand-in helper that records its arguments and stdin, then runs `body`.
    func play(_ body: String) throws -> GooglePlay {
        let script = work.appendingPathComponent("bedrock-gplay")
        try """
        #!/bin/bash
        printf '%s\\n' "$@" > "\(work.path)/args"
        cat > "\(work.path)/stdin"
        \(body)
        """.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return GooglePlay(helper: script, state: state, credentials: credentials)
    }

    func recorded(_ name: String) throws -> String {
        try String(contentsOf: work.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func signInSavesAccount() async throws {
        let play = try play("echo 'email kid@example.com'; echo 'token aas_et/secret'")
        #expect(try await play.signIn(oauthToken: "oauth2_4/x") == "kid@example.com")
        #expect(credentials.load() == account)
        #expect(play.isSignedIn)
        #expect(!fm.fileExists(atPath: state.appendingPathComponent("playdl.conf").path))
    }

    @Test func signInWithoutTokenSavesNothing() async throws {
        let play = try play("echo 'email kid@example.com'")
        await #expect(throws: GooglePlayError.failed("Google sign-in returned no token")) {
            try await play.signIn(oauthToken: "oauth2_4/x")
        }
        #expect(credentials.load() == nil)
    }

    @Test func latestSendsAccountOnStdin() async throws {
        try credentials.save(account)
        let play = try play("echo 'version-code 5'")
        #expect(try await play.latestVersionCode() == 5)
        #expect(try recorded("stdin") == "kid@example.com\naas_et/secret\n")
        #expect(try !recorded("args").contains("secret"))
    }

    @Test func noAccountNeedsSignInWithoutRunningHelper() async throws {
        let play = try play("touch \"\(work.path)/ran\"")
        await #expect(throws: GooglePlayError.signInNeeded("not signed in")) {
            try await play.latestVersionCode()
        }
        #expect(!fm.fileExists(atPath: work.appendingPathComponent("ran").path))
    }

    @Test func migrationMovesLegacyFile() throws {
        try fm.createDirectory(at: state, withIntermediateDirectories: true)
        try "user_email = kid@example.com\nuser_token = aas_et/secret\n"
            .write(to: state.appendingPathComponent("playdl.conf"), atomically: true, encoding: .utf8)
        let play = try play("")
        try play.migrateLegacyFile()
        #expect(credentials.load() == account)
        #expect(!fm.fileExists(atPath: state.appendingPathComponent("playdl.conf").path))
    }

    @Test func migrationDropsEmptyToken() throws {
        try fm.createDirectory(at: state, withIntermediateDirectories: true)
        try "user_email = kid@example.com\nuser_token = \n"
            .write(to: state.appendingPathComponent("playdl.conf"), atomically: true, encoding: .utf8)
        let play = try play("")
        try play.migrateLegacyFile()
        #expect(credentials.load() == nil)
        #expect(!fm.fileExists(atPath: state.appendingPathComponent("playdl.conf").path))
    }

    @Test func signOutClearsAccount() throws {
        try credentials.save(account)
        let play = try play("")
        try play.signOut()
        #expect(credentials.load() == nil)
        #expect(!play.isSignedIn)
    }

    @Test func keychainRoundTrip() throws {
        let keychain = KeychainCredentials(service: "io.github.icehunter.bedrock-launcher.test-\(UUID().uuidString)")
        defer { try? keychain.delete() }
        #expect(keychain.load() == nil)
        try keychain.save(account)
        #expect(keychain.load() == account)
        try keychain.save(GoogleAccount(email: "kid@example.com", token: "aas_et/newer"))
        #expect(keychain.load()?.token == "aas_et/newer")
        try keychain.delete()
        #expect(keychain.load() == nil)
        try keychain.delete()
    }
}
