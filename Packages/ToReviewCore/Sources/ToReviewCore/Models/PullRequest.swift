import Foundation

/// CI state of the head commit, normalized across providers.
public enum CIStatus: String, Codable, Sendable, Hashable {
    case success
    case failure
    case pending
    case running
    case canceled
    case skipped
    /// Provider returned no pipeline / checks for the head commit.
    case none
}

public struct PRAuthor: Codable, Hashable, Sendable {
    public var login: String
    public var name: String?
    public var avatarURL: URL?

    public init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return login
    }
}

/// A pull request (GitHub) or merge request (GitLab), normalized.
public struct PullRequest: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity across syncs: account + project path + number.
    public struct ID: Hashable, Codable, Sendable, CustomStringConvertible {
        public var accountID: UUID
        public var project: String
        public var number: Int

        public init(accountID: UUID, project: String, number: Int) {
            self.accountID = accountID
            self.project = project
            self.number = number
        }

        /// Compact string form used for `Set<String>` persistence.
        public var description: String { "\(accountID.uuidString)|\(project)|\(number)" }
    }

    public var id: ID
    public var kind: ProviderKind
    public var title: String
    public var url: URL
    public var author: PRAuthor
    public var isDraft: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var ciStatus: CIStatus
    public var approvalsCount: Int
    public var approvedByMe: Bool
    public var commentsCount: Int
    public var isReviewRequested: Bool
    public var isAssigned: Bool
    public var isAuthoredByMe: Bool

    public init(
        id: ID,
        kind: ProviderKind,
        title: String,
        url: URL,
        author: PRAuthor,
        isDraft: Bool,
        createdAt: Date,
        updatedAt: Date,
        ciStatus: CIStatus,
        approvalsCount: Int,
        approvedByMe: Bool,
        commentsCount: Int,
        isReviewRequested: Bool,
        isAssigned: Bool,
        isAuthoredByMe: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.author = author
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ciStatus = ciStatus
        self.approvalsCount = approvalsCount
        self.approvedByMe = approvedByMe
        self.commentsCount = commentsCount
        self.isReviewRequested = isReviewRequested
        self.isAssigned = isAssigned
        self.isAuthoredByMe = isAuthoredByMe
    }

    public var accountID: UUID { id.accountID }
    public var project: String { id.project }
    public var number: Int { id.number }

    /// Short project name without the namespace, e.g. `repo` for `owner/repo`.
    public var projectShortName: String {
        id.project.split(separator: "/").last.map(String.init) ?? id.project
    }

    /// `owner/repo!42` for GitLab, `owner/repo#42` for GitHub.
    public var reference: String {
        "\(id.project)\(kind == .gitlab ? "!" : "#")\(id.number)"
    }

    public var shortReference: String {
        "\(projectShortName)\(kind == .gitlab ? "!" : "#")\(id.number)"
    }
}
