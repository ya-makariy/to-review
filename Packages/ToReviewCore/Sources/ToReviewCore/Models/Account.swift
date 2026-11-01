import Foundation

/// A connected GitHub or GitLab identity. Tokens are stored separately in the Keychain,
/// keyed by `id`, so this struct can be persisted in plain JSON.
public struct Account: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ProviderKind
    /// Host root, e.g. `https://github.com` or `https://gitlab.company.com`.
    public var baseURL: URL
    public var authMethod: AuthMethod
    /// Login as reported by the provider (`viewer.login` / `currentUser.username`).
    public var username: String
    public var displayName: String
    public var avatarURL: URL?
    /// Optional user-provided label, e.g. "Work" or "Personal".
    public var label: String?
    public var isEnabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: ProviderKind,
        baseURL: URL,
        authMethod: AuthMethod,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        label: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.baseURL = baseURL
        self.authMethod = authMethod
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.label = label
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Title shown in lists: the label if present, otherwise `username@host`.
    public var title: String {
        if let label, !label.isEmpty { return label }
        return "\(username)@\(host)"
    }

    public var host: String {
        baseURL.host() ?? baseURL.absoluteString
    }

    /// True for github.com / gitlab.com, where OAuth device flow is available.
    public var isCloudHost: Bool {
        host == kind.defaultBaseURL.host()
    }
}
