import Foundation
import Security

struct DeviceCodePrompt {
    let userCode: String
    let verificationURI: URL
    let deviceCode: String
    let interval: Int
    let expiresIn: Int
}

struct SignInResult {
    let gamertag: String
    let userHash: String
    let xstsToken: String
    let refreshToken: String
}

enum MSAuthError: LocalizedError {
    case badResponse(String)
    case declined(String)
    case expired
    case xbox(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let s): return "Unexpected response: \(s)"
        case .declined(let s): return "Microsoft refused the request: \(s)"
        case .expired: return "The sign-in code expired. Try again."
        case .xbox(let s): return "Xbox Live refused the account (\(s)). Check the account has an Xbox profile."
        }
    }
}

/// Microsoft device-code sign-in, then Xbox Live (XBL) and XSTS tokens.
/// Needs an Azure app registration: personal accounts allowed, "Allow public client flows" on.
struct MSAuth {
    let clientID: String

    func requestDeviceCode() async throws -> DeviceCodePrompt {
        let r = try await form("https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
                               ["client_id": clientID, "scope": "XboxLive.signin offline_access"])
        guard let code = r["user_code"] as? String,
              let dev = r["device_code"] as? String,
              let uri = (r["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw MSAuthError.declined((r["error_description"] as? String) ?? "\(r)")
        }
        return DeviceCodePrompt(userCode: code, verificationURI: uri, deviceCode: dev,
                                interval: r["interval"] as? Int ?? 5,
                                expiresIn: r["expires_in"] as? Int ?? 900)
    }

    func completeSignIn(_ p: DeviceCodePrompt) async throws -> SignInResult {
        let (msToken, refresh) = try await pollToken(p)

        let xbl = try await json("https://user.auth.xboxlive.com/user/authenticate", [
            "Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(msToken)"],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT",
        ])
        guard let xblToken = xbl["Token"] as? String else { throw MSAuthError.badResponse("\(xbl)") }

        let xsts = try await json("https://xsts.auth.xboxlive.com/xsts/authorize", [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [xblToken]],
            "RelyingParty": "http://xboxlive.com",
            "TokenType": "JWT",
        ])
        if let x = xsts["XErr"] { throw MSAuthError.xbox("\(x)") }
        guard let token = xsts["Token"] as? String,
              let claims = xsts["DisplayClaims"] as? [String: Any],
              let xui = (claims["xui"] as? [[String: Any]])?.first,
              let uhs = xui["uhs"] as? String else {
            throw MSAuthError.badResponse("\(xsts)")
        }
        return SignInResult(gamertag: xui["gtg"] as? String ?? "(no gamertag)",
                            userHash: uhs, xstsToken: token, refreshToken: refresh)
    }

    private func pollToken(_ p: DeviceCodePrompt) async throws -> (String, String) {
        var interval = p.interval
        let deadline = Date().addingTimeInterval(Double(p.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let r = try await form("https://login.microsoftonline.com/consumers/oauth2/v2.0/token", [
                "client_id": clientID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": p.deviceCode,
            ])
            if let at = r["access_token"] as? String, let rt = r["refresh_token"] as? String {
                return (at, rt)
            }
            switch r["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            default: throw MSAuthError.declined((r["error_description"] as? String) ?? "\(r)")
            }
        }
        throw MSAuthError.expired
    }

    private func form(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v)"
        }.joined(separator: "&")
        req.httpBody = Data(body.utf8)
        return try await send(req)
    }

    private func json(_ url: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MSAuthError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return obj
    }
}

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "BedrockLauncher",
         kSecAttrAccount as String: key]
    }

    static func save(_ key: String, _ value: String) {
        SecItemDelete(base(key) as CFDictionary)
        var add = base(key)
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
