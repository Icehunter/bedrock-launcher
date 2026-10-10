import Foundation

/// Compares the running version with the newest GitHub Release. Only reports;
/// the launcher does not replace itself.
enum UpdateCheck {
    struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// The newer release, if there is one.
    static func newerRelease(than current: String) async -> Release? {
        guard current != "development" else { return nil }
        var request = URLRequest(url: AppInfo.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return nil }
        return isNewer(release.tag_name, than: current) ? release : nil
    }

    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        return parts(current).lexicographicallyPrecedes(parts(tag))
    }
}
