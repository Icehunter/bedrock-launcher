import Foundation

public enum WebViewURL {
    /// True when `url` starts with `prefix`, the URL the game waits for at the
    /// end of sign-in. The scheme part is compared ignoring case.
    public static func isEnd(_ url: URL, prefix: String) -> Bool {
        normalized(url.absoluteString).hasPrefix(normalized(prefix))
    }

    private static func normalized(_ s: String) -> String {
        guard let r = s.range(of: "://") else { return s }
        return s[..<r.lowerBound].lowercased() + s[r.lowerBound...]
    }
}
