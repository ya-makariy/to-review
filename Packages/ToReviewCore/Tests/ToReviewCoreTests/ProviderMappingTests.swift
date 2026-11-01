import Foundation
import Testing
@testable import ToReviewCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private let githubAccount = Account(
    kind: .github, baseURL: URL(string: "https://github.com")!, authMethod: .personalAccessToken,
    username: "me", displayName: "Me"
)

private let gitlabAccount = Account(
    kind: .gitlab, baseURL: URL(string: "https://gitlab.example.com")!, authMethod: .personalAccessToken,
    username: "me", displayName: "Me"
)

@Suite struct GitHubMappingTests {
    @Test func mapsAndMergesSearchResults() throws {
        let data = try GraphQLClient.decoder.decode(GitHubProvider.SearchData.self, from: fixture("github_search"))
        let prs = GitHubProvider.map(data, account: githubAccount)

        // 42 appears in both review and assigned: merged into one entry.
        #expect(prs.count == 4)
        let pr42 = try #require(prs.first { $0.number == 42 })
        #expect(pr42.isReviewRequested && pr42.isAssigned && !pr42.isAuthoredByMe)
        #expect(pr42.project == "acme/widgets")
        #expect(pr42.reference == "acme/widgets#42")
        #expect(pr42.author.displayName == "Alice")
        #expect(pr42.ciStatus == .success)
        #expect(pr42.approvalsCount == 1)
        #expect(pr42.approvedByMe == false)
        #expect(pr42.commentsCount == 5)

        let pr99 = try #require(prs.first { $0.number == 99 })
        #expect(pr99.approvedByMe == true, "login comparison is case-insensitive")
        #expect(pr99.ciStatus == .failure)

        let mine = try #require(prs.first { $0.number == 5 })
        #expect(mine.isAuthoredByMe)
        #expect(mine.ciStatus == .pending)
    }

    @Test func endpointSelection() {
        #expect(GitHubProvider.endpoint(for: URL(string: "https://github.com")!).absoluteString == "https://api.github.com/graphql")
        #expect(GitHubProvider.endpoint(for: URL(string: "https://ghe.corp.com")!).absoluteString == "https://ghe.corp.com/api/graphql")
    }
}

@Suite struct GitLabMappingTests {
    @Test func mapsPageAndResolvesRelativeAvatar() throws {
        let page = try GraphQLClient.decoder.decode(GitLabProvider.PageData.self, from: fixture("gitlab_page"))
        let nodes = try #require(page.currentUser?.items.nodes)
        let prs = GitLabProvider.map(nodes, role: .review, account: gitlabAccount)

        #expect(prs.count == 2)
        let mr = try #require(prs.first { $0.number == 12 })
        #expect(mr.reference == "platform/infra!12")
        #expect(mr.shortReference == "infra!12")
        #expect(mr.author.avatarURL?.absoluteString == "https://gitlab.example.com/uploads/-/system/user/avatar/3/avatar.png")
        #expect(mr.ciStatus == .running)
        #expect(mr.approvalsCount == 2)
        #expect(mr.approvedByMe)
        #expect(mr.commentsCount == 4)
        #expect(mr.isReviewRequested && !mr.isAssigned)

        let draft = try #require(prs.first { $0.number == 13 })
        #expect(draft.isDraft)
        #expect(draft.ciStatus == .none)
        #expect(draft.commentsCount == 0)
    }

    @Test func parsesBothDateFlavours() throws {
        let page = try GraphQLClient.decoder.decode(GitLabProvider.PageData.self, from: fixture("gitlab_page"))
        let node = try #require(page.currentUser?.items.nodes.first)
        #expect(node.updatedAt > node.createdAt)
    }
}
