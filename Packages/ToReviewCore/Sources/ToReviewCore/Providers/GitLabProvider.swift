import Foundation

/// GitLab.com and self-managed GitLab via the GraphQL API.
public struct GitLabProvider: GitProvider {
    public let account: Account
    private let client: GraphQLClient

    public init(account: Account, token: String, session: URLSession = .shared) {
        self.account = account
        self.client = GraphQLClient(endpoint: Self.endpoint(for: account.baseURL), token: token, session: session)
    }

    public static func endpoint(for baseURL: URL) -> URL {
        baseURL.appendingPathComponent("api/graphql")
    }

    // MARK: validate

    private struct CurrentUserData: Decodable {
        struct User: Decodable { let username: String; let name: String?; let avatarUrl: String? }
        let currentUser: User?
    }

    public static func validate(baseURL: URL, token: String, session: URLSession) async throws -> ProviderIdentity {
        let client = GraphQLClient(endpoint: endpoint(for: baseURL), token: token, session: session)
        let data: CurrentUserData = try await client.execute("query { currentUser { username name avatarUrl } }")
        guard let user = data.currentUser else { throw ProviderError.unauthorized }
        return ProviderIdentity(login: user.username, name: user.name, avatarURL: resolve(user.avatarUrl, against: baseURL))
    }

    /// Self-managed instances return avatar paths relative to the host.
    static func resolve(_ string: String?, against baseURL: URL) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: fetch

    enum Role: String, CaseIterable {
        case review = "reviewRequestedMergeRequests"
        case assigned = "assignedMergeRequests"
        case authored = "authoredMergeRequests"
    }

    static func query(for role: Role) -> String {
        """
        query($after: String) {
          currentUser {
            items: \(role.rawValue)(state: opened, first: 100, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes {
                iid title webUrl draft createdAt updatedAt
                project { fullPath }
                author { username name avatarUrl }
                headPipeline { status }
                approvedBy { nodes { username } }
                userNotesCount
              }
            }
          }
        }
        """
    }

    struct PageData: Decodable {
        let currentUser: CurrentUser?

        struct CurrentUser: Decodable { let items: Connection }
        struct Connection: Decodable { let pageInfo: PageInfo; let nodes: [Node] }
        struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }

        struct Node: Decodable {
            let iid: String
            let title: String
            let webUrl: URL
            let draft: Bool
            let createdAt: Date
            let updatedAt: Date
            let project: Project
            let author: Author?
            let headPipeline: Pipeline?
            let approvedBy: Users
            let userNotesCount: Int?

            struct Project: Decodable { let fullPath: String }
            struct Author: Decodable { let username: String; let name: String?; let avatarUrl: String? }
            struct Pipeline: Decodable { let status: String }
            struct Users: Decodable { let nodes: [User] }
            struct User: Decodable { let username: String }
        }
    }

    public func fetchPullRequests() async throws -> [PullRequest] {
        try await withThrowingTaskGroup(of: (Role, [PageData.Node]).self) { group in
            for role in Role.allCases {
                group.addTask { (role, try await fetchAll(role)) }
            }
            var result: [PullRequest] = []
            for try await (role, nodes) in group {
                result += Self.map(nodes, role: role, account: account)
            }
            return result.mergedByID()
        }
    }

    private func fetchAll(_ role: Role, maxPages: Int = 3) async throws -> [PageData.Node] {
        var nodes: [PageData.Node] = []
        var after: String? = nil
        for _ in 0..<maxPages {
            let page: PageData = try await client.execute(Self.query(for: role), variables: ["after": after])
            guard let items = page.currentUser?.items else { throw ProviderError.unauthorized }
            nodes += items.nodes
            guard items.pageInfo.hasNextPage, let cursor = items.pageInfo.endCursor else { break }
            after = cursor
        }
        return nodes
    }

    static func map(_ nodes: [PageData.Node], role: Role, account: Account) -> [PullRequest] {
        let me = account.username.lowercased()
        return nodes.compactMap { node in
            guard let number = Int(node.iid) else { return nil }
            let approvers = node.approvedBy.nodes.map { $0.username.lowercased() }
            return PullRequest(
                id: .init(accountID: account.id, project: node.project.fullPath, number: number),
                kind: .gitlab,
                title: node.title,
                url: node.webUrl,
                author: PRAuthor(
                    login: node.author?.username ?? "unknown",
                    name: node.author?.name,
                    avatarURL: resolve(node.author?.avatarUrl, against: account.baseURL)
                ),
                isDraft: node.draft,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                ciStatus: ciStatus(node.headPipeline?.status),
                approvalsCount: approvers.count,
                approvedByMe: approvers.contains(me),
                commentsCount: node.userNotesCount ?? 0,
                isReviewRequested: role == .review,
                isAssigned: role == .assigned,
                isAuthoredByMe: role == .authored || node.author?.username.lowercased() == me
            )
        }
    }

    static func ciStatus(_ status: String?) -> CIStatus {
        switch status {
        case "SUCCESS": .success
        case "FAILED": .failure
        case "RUNNING": .running
        case "CANCELED", "CANCELING": .canceled
        case "SKIPPED": .skipped
        case "CREATED", "WAITING_FOR_RESOURCE", "PREPARING", "PENDING", "MANUAL", "SCHEDULED", "WAITING_FOR_CALLBACK": .pending
        case nil: .none
        default: .pending
        }
    }
}
