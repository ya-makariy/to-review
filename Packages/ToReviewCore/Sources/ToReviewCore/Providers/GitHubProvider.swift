import Foundation

/// GitHub.com and GitHub Enterprise via the GraphQL v4 API.
public struct GitHubProvider: GitProvider {
    public let account: Account
    private let client: GraphQLClient

    public init(account: Account, token: String, session: URLSession = .shared) {
        self.account = account
        self.client = GraphQLClient(endpoint: Self.endpoint(for: account.baseURL), token: token, session: session)
    }

    /// github.com uses a separate API host; Enterprise serves GraphQL under `/api/graphql`.
    public static func endpoint(for baseURL: URL) -> URL {
        if baseURL.host() == "github.com" { return URL(string: "https://api.github.com/graphql")! }
        return baseURL.appendingPathComponent("api/graphql")
    }

    // MARK: validate

    private struct ViewerData: Decodable {
        struct Viewer: Decodable { let login: String; let name: String?; let avatarUrl: URL? }
        let viewer: Viewer
    }

    public static func validate(baseURL: URL, token: String, session: URLSession) async throws -> ProviderIdentity {
        let client = GraphQLClient(endpoint: endpoint(for: baseURL), token: token, session: session)
        let data: ViewerData = try await client.execute("query { viewer { login name avatarUrl } }")
        return ProviderIdentity(login: data.viewer.login, name: data.viewer.name, avatarURL: data.viewer.avatarUrl)
    }

    // MARK: fetch

    static let query = """
    query($reviewQ: String!, $assignedQ: String!, $authoredQ: String!) {
      review: search(query: $reviewQ, type: ISSUE, first: 100) { ...PRs }
      assigned: search(query: $assignedQ, type: ISSUE, first: 100) { ...PRs }
      authored: search(query: $authoredQ, type: ISSUE, first: 100) { ...PRs }
    }
    fragment PRs on SearchResultItemConnection {
      nodes {
        ... on PullRequest {
          number title url isDraft createdAt updatedAt
          repository { nameWithOwner }
          author { login avatarUrl ... on User { name } }
          latestOpinionatedReviews(first: 100) { nodes { state author { login } } }
          comments { totalCount }
          reviewThreads { totalCount }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
      }
    }
    """

    struct SearchData: Decodable {
        let review: Connection
        let assigned: Connection
        let authored: Connection

        struct Connection: Decodable { let nodes: [Node?] }

        struct Node: Decodable {
            let number: Int
            let title: String
            let url: URL
            let isDraft: Bool
            let createdAt: Date
            let updatedAt: Date
            let repository: Repository
            let author: Author?
            let latestOpinionatedReviews: Reviews
            let comments: Count
            let reviewThreads: Count
            let commits: Commits

            struct Repository: Decodable { let nameWithOwner: String }
            struct Author: Decodable { let login: String; let avatarUrl: URL?; let name: String? }
            struct Reviews: Decodable { let nodes: [Review] }
            struct Review: Decodable { let state: String; let author: Login? }
            struct Login: Decodable { let login: String }
            struct Count: Decodable { let totalCount: Int }
            struct Commits: Decodable { let nodes: [CommitNode] }
            struct CommitNode: Decodable { let commit: Commit }
            struct Commit: Decodable { let statusCheckRollup: Rollup? }
            struct Rollup: Decodable { let state: String }
        }
    }

    public func fetchPullRequests() async throws -> [PullRequest] {
        let base = "is:pr is:open archived:false"
        let data: SearchData = try await client.execute(Self.query, variables: [
            "reviewQ": "\(base) review-requested:@me",
            "assignedQ": "\(base) assignee:@me",
            "authoredQ": "\(base) author:@me",
        ])
        return Self.map(data, account: account)
    }

    static func map(_ data: SearchData, account: Account) -> [PullRequest] {
        let me = account.username.lowercased()
        func convert(_ nodes: [SearchData.Node?], review: Bool, assigned: Bool, authored: Bool) -> [PullRequest] {
            nodes.compactMap { $0 }.map { node in
                let approvals = node.latestOpinionatedReviews.nodes.filter { $0.state == "APPROVED" }
                return PullRequest(
                    id: .init(accountID: account.id, project: node.repository.nameWithOwner, number: node.number),
                    kind: .github,
                    title: node.title,
                    url: node.url,
                    author: PRAuthor(
                        login: node.author?.login ?? "ghost",
                        name: node.author?.name,
                        avatarURL: node.author?.avatarUrl
                    ),
                    isDraft: node.isDraft,
                    createdAt: node.createdAt,
                    updatedAt: node.updatedAt,
                    ciStatus: ciStatus(node.commits.nodes.first?.commit.statusCheckRollup?.state),
                    approvalsCount: approvals.count,
                    approvedByMe: approvals.contains { $0.author?.login.lowercased() == me },
                    commentsCount: node.comments.totalCount + node.reviewThreads.totalCount,
                    isReviewRequested: review,
                    isAssigned: assigned,
                    isAuthoredByMe: authored || node.author?.login.lowercased() == me
                )
            }
        }
        return (
            convert(data.review.nodes, review: true, assigned: false, authored: false)
            + convert(data.assigned.nodes, review: false, assigned: true, authored: false)
            + convert(data.authored.nodes, review: false, assigned: false, authored: true)
        ).mergedByID()
    }

    static func ciStatus(_ state: String?) -> CIStatus {
        switch state {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        case nil: .none
        default: .pending
        }
    }
}
