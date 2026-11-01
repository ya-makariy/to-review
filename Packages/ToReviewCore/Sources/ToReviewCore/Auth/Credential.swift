import Foundation

/// Secret material for one account. Stored as JSON in the Keychain.
public struct Credential: Codable, Hashable, Sendable {
    public var accessToken: String
    /// Present for OAuth flows that issue refresh tokens (GitLab).
    public var refreshToken: String?
    /// When `accessToken` stops working. `nil` means it does not expire.
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the token expires within `leeway` seconds and we hold a refresh token.
    public func needsRefresh(leeway: TimeInterval = 120, now: Date = Date()) -> Bool {
        guard let expiresAt, refreshToken != nil else { return false }
        return expiresAt.timeIntervalSince(now) < leeway
    }
}
