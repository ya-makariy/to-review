import Foundation

/// Which hosting service an account belongs to.
public enum ProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case github
    case gitlab

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    /// Default cloud host for this provider.
    public var defaultBaseURL: URL {
        switch self {
        case .github: URL(string: "https://github.com")!
        case .gitlab: URL(string: "https://gitlab.com")!
        }
    }

    /// Human term used by the provider for a code review request.
    public var requestNoun: String {
        switch self {
        case .github: "PR"
        case .gitlab: "MR"
        }
    }

    /// Token scopes the user needs to grant for a personal access token.
    public var requiredScopesHint: String {
        switch self {
        case .github: "Classic token: `repo`, `read:user`. Fine-grained token: Pull requests → Read, Metadata → Read."
        case .gitlab: "Scope: `read_api`."
        }
    }
}

/// How the credentials for an account were obtained.
public enum AuthMethod: String, Codable, Sendable {
    case personalAccessToken
    case oauthDevice
}
