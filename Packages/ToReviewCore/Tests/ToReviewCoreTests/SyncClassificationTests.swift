import Foundation
import Testing
@testable import ToReviewCore

private let accountID = UUID()

private func pr(
    _ number: Int,
    review: Bool = false, assigned: Bool = false, mine: Bool = false,
    draft: Bool = false, approvedByMe: Bool = false, updated: TimeInterval = 0
) -> PullRequest {
    PullRequest(
        id: .init(accountID: accountID, project: "acme/repo", number: number),
        kind: .github, title: "PR \(number)", url: URL(string: "https://example.com/\(number)")!,
        author: PRAuthor(login: mine ? "me" : "other"), isDraft: draft,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: updated),
        ciStatus: .none, approvalsCount: approvedByMe ? 1 : 0, approvedByMe: approvedByMe, commentsCount: 0,
        isReviewRequested: review, isAssigned: assigned, isAuthoredByMe: mine
    )
}

@Suite struct ClassificationTests {
    @Test func incomingIncludesReviewersAndAssignees() {
        let result = SyncEngine.classify([
            pr(1, review: true, updated: 10),
            pr(2, assigned: true, updated: 20),
            pr(3, review: true, mine: true),      // my own PR where I'm also reviewer → outgoing only
            pr(4, review: true, draft: true),     // drafts hidden
            pr(5, review: true, approvedByMe: true),
        ], settings: AppSettings(hideApprovedByMe: true))

        #expect(result.incoming.map(\.number) == [2, 1], "sorted by updatedAt desc")
        #expect(result.outgoing.map(\.number) == [3])
    }

    @Test func approvedByMeIsKeptWhenSettingOff() {
        let result = SyncEngine.classify([pr(5, review: true, approvedByMe: true)], settings: AppSettings(hideApprovedByMe: false))
        #expect(result.incoming.map(\.number) == [5])
    }

    @Test func outgoingKeepsDrafts() {
        let result = SyncEngine.classify([pr(9, mine: true, draft: true)], settings: .default)
        #expect(result.outgoing.count == 1)
        #expect(result.incoming.isEmpty)
    }
}

@Suite struct SeenStoreTests {
    @Test func marksAndPrunes() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("toreview-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SeenStore(directory: directory)
        let a = PullRequest.ID(accountID: accountID, project: "p", number: 1)
        let b = PullRequest.ID(accountID: accountID, project: "p", number: 2)
        store.forget(accountID: accountID)

        store.markSeen([a, b])
        #expect(store.isSeen(a) && store.isSeen(b))

        store.retainOnly([a])
        #expect(store.isSeen(a))
        #expect(!store.isSeen(b))

        #expect(!store.hasCompletedFirstSync(accountID))
        store.markFirstSyncCompleted(accountID)
        #expect(store.hasCompletedFirstSync(accountID))

        store.forget(accountID: accountID)
        #expect(!store.isSeen(a))
        #expect(!store.hasCompletedFirstSync(accountID))
    }
}

@Suite struct SnapshotCodingTests {
    @Test func roundTripsThroughJSON() throws {
        // Whole-second dates: ISO 8601 encoding drops sub-second precision.
        let account = Account(kind: .gitlab, baseURL: URL(string: "https://gitlab.com")!, authMethod: .oauthDevice,
                              username: "me", displayName: "Me", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = Snapshot(generatedAt: Date(timeIntervalSince1970: 1_700_000_500), accounts: [
            AccountSnapshot(account: account, status: .warning(message: "offline", lastSuccess: Date(timeIntervalSince1970: 100)),
                            incoming: [pr(1, review: true)], unseenIncomingIDs: [pr(1).id]),
        ])
        let data = try SharedStorage.makeEncoder().encode(snapshot)
        let decoded = try SharedStorage.makeDecoder().decode(Snapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.hasUnseen)
        #expect(decoded.hasWarnings && !decoded.hasErrors)
        #expect(decoded.incomingCount == 1)
    }

    @Test func settingsDecodeWithMissingOptionalKeys() throws {
        let json = #"{"pollInterval":300,"statusBarMode":"incomingOnly","launchAtLogin":false,"notificationsEnabled":true,"hideApprovedByMe":true,"listFields":{"showAuthor":true,"showCIStatus":true,"showUpdatedAt":true,"showApprovals":true,"showComments":true},"widgetFields":{"showAuthor":true,"showCIStatus":false,"showUpdatedAt":false,"showApprovals":false,"showComments":false}}"#
        let settings = try SharedStorage.makeDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.statusBarMode == .incomingOnly)
        #expect(settings.oauthClientID(for: .github) == nil)
    }
}
