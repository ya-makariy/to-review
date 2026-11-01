import Foundation

public enum PollInterval: Int, Codable, Sendable, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var displayName: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        }
    }
}

public enum StatusBarMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// `↓ 3  ↑ 2`
    case incomingAndOutgoing
    /// `↓ 3`
    case incomingOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .incomingAndOutgoing: "Incoming and outgoing"
        case .incomingOnly: "Incoming only"
        }
    }
}

/// Which optional columns a PR row shows. Project, number and title are always visible.
public struct DisplayFields: Codable, Hashable, Sendable {
    public var showAuthor: Bool
    public var showCIStatus: Bool
    public var showUpdatedAt: Bool
    public var showApprovals: Bool
    public var showComments: Bool

    public init(
        showAuthor: Bool = true,
        showCIStatus: Bool = true,
        showUpdatedAt: Bool = true,
        showApprovals: Bool = true,
        showComments: Bool = true
    ) {
        self.showAuthor = showAuthor
        self.showCIStatus = showCIStatus
        self.showUpdatedAt = showUpdatedAt
        self.showApprovals = showApprovals
        self.showComments = showComments
    }

    public static let all = DisplayFields()
    /// Denser default for widgets.
    public static let compact = DisplayFields(showAuthor: true, showCIStatus: true, showUpdatedAt: false, showApprovals: false, showComments: false)
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var pollInterval: PollInterval
    public var statusBarMode: StatusBarMode
    public var launchAtLogin: Bool
    public var notificationsEnabled: Bool
    /// Drop incoming PRs the user has already approved.
    public var hideApprovedByMe: Bool
    public var listFields: DisplayFields
    public var widgetFields: DisplayFields
    /// Overrides for the compiled-in OAuth client ids (see `OAuthConfig`).
    public var githubOAuthClientID: String?
    public var gitlabOAuthClientID: String?

    public init(
        pollInterval: PollInterval = .fiveMinutes,
        statusBarMode: StatusBarMode = .incomingAndOutgoing,
        launchAtLogin: Bool = true,
        notificationsEnabled: Bool = true,
        hideApprovedByMe: Bool = true,
        listFields: DisplayFields = .all,
        widgetFields: DisplayFields = .compact,
        githubOAuthClientID: String? = nil,
        gitlabOAuthClientID: String? = nil
    ) {
        self.pollInterval = pollInterval
        self.statusBarMode = statusBarMode
        self.launchAtLogin = launchAtLogin
        self.notificationsEnabled = notificationsEnabled
        self.hideApprovedByMe = hideApprovedByMe
        self.listFields = listFields
        self.widgetFields = widgetFields
        self.githubOAuthClientID = githubOAuthClientID
        self.gitlabOAuthClientID = gitlabOAuthClientID
    }

    /// Effective OAuth client id for a provider, or `nil` if device flow is unavailable.
    public func oauthClientID(for kind: ProviderKind) -> String? {
        let override = switch kind {
        case .github: githubOAuthClientID
        case .gitlab: gitlabOAuthClientID
        }
        if let override, !override.isEmpty { return override }
        let builtIn = OAuthConfig.clientID(for: kind)
        return builtIn.isEmpty ? nil : builtIn
    }

    public static let `default` = AppSettings()
}
