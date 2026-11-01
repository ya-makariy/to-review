import CryptoKit
import Foundation

/// Downloads avatars once and keeps them as files in the shared directory.
///
/// Needed because self-managed GitLab serves avatars behind authentication (a plain
/// `AsyncImage` gets a redirect to the sign-in page), and because widgets cannot load
/// images from the network at all.
public struct AvatarCache: Sendable {
    private let directory: URL
    private let maxAge: TimeInterval

    public init(directory: URL = SharedStorage.directoryOrTemporary(), maxAge: TimeInterval = 7 * 24 * 3600) {
        self.directory = directory.appendingPathComponent("avatars", isDirectory: true)
        self.maxAge = maxAge
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Where the cached copy of `remote` lives (whether or not it exists yet).
    public func localURL(for remote: URL) -> URL {
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    /// Cached file if present, regardless of age.
    public func cachedURL(for remote: URL?) -> URL? {
        guard let remote else { return nil }
        let url = localURL(for: remote)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func isFresh(_ url: URL) -> Bool {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
        return Date().timeIntervalSince(date) < maxAge
    }

    /// Downloads `remote` unless a fresh copy exists. Credentials are sent only when the
    /// avatar is hosted on `authHost`, so they never leak to CDNs.
    ///
    /// Self-managed GitLab protects `/uploads/` and ignores `Authorization: Bearer` there,
    /// so we fall back to `PRIVATE-TOKEN` and then to the `private_token` query parameter.
    public func ensureCached(_ remote: URL, token: String?, authHost: String?, session: URLSession = .shared) async {
        let local = localURL(for: remote)
        if FileManager.default.fileExists(atPath: local.path), isFresh(local) { return }

        let authenticated = token != nil && authHost != nil && remote.host() == authHost
        var attempts: [URLRequest] = [URLRequest(url: remote)]
        if authenticated, let token {
            var bearer = URLRequest(url: remote)
            bearer.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var header = URLRequest(url: remote)
            header.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            var components = URLComponents(url: remote, resolvingAgainstBaseURL: false)
            let existing = components?.queryItems ?? []
            components?.queryItems = existing + [URLQueryItem(name: "private_token", value: token)]
            attempts = [bearer, header] + (components?.url.map { [URLRequest(url: $0)] } ?? [])
        }

        for var request in attempts {
            request.timeoutInterval = 15
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }
                if http.statusCode == 200,
                   http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("image/") ?? true,
                   !data.isEmpty {
                    try data.write(to: local, options: .atomic)
                    return
                }
                if http.statusCode != 401 && http.statusCode != 403 { break }
            } catch {
                SharedStorage.log.debug("Avatar download failed for \(remote.host() ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        SharedStorage.log.notice("Avatar unavailable from \(remote.host() ?? "?", privacy: .public)")
    }

    /// Caches every distinct avatar referenced by `prs` and the account itself.
    public func cacheAvatars(for prs: [PullRequest], account: Account, token: String, session: URLSession = .shared) async {
        var urls = Set(prs.compactMap(\.author.avatarURL))
        if let own = account.avatarURL { urls.insert(own) }
        let host = account.baseURL.host()
        await withTaskGroup(of: Void.self) { group in
            for url in urls.prefix(60) {
                group.addTask { await ensureCached(url, token: token, authHost: host, session: session) }
            }
        }
    }
}
