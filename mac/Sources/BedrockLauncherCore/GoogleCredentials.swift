import Foundation
import Security

/// The signed-in Google account: its email and the long-lived token Google
/// Play gives after sign-in. The token works like a password.
public struct GoogleAccount: Codable, Equatable, Sendable {
    public let email: String
    public let token: String

    public init(email: String, token: String) {
        self.email = email
        self.token = token
    }
}

/// Where the Google account is kept.
public protocol GoogleCredentials: Sendable {
    func load() -> GoogleAccount?
    func save(_ account: GoogleAccount) throws
    func delete() throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Keeps the account in the user's Keychain, readable by this app only
/// unless the user allows another one.
public struct KeychainCredentials: GoogleCredentials {
    public let service: String
    public let account: String

    public init(service: String = "io.github.icehunter.bedrock-launcher.google", account: String = "google-account") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> GoogleAccount? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }

    public func save(_ value: GoogleAccount) throws {
        let data = try JSONEncoder().encode(value)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Bedrock Launcher Google account"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Keeps the account in memory, for tests.
public final class MemoryCredentials: GoogleCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var value: GoogleAccount?

    public init() {}

    public func load() -> GoogleAccount? { lock.withLock { value } }
    public func save(_ account: GoogleAccount) throws { lock.withLock { value = account } }
    public func delete() throws { lock.withLock { value = nil } }
}
